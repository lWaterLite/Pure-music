use std::fs::File;
use std::path::Path;

use ebur128::{EbuR128, Mode};
use symphonia::core::audio::sample::Sample;
use symphonia::core::codecs::audio::AudioDecoderOptions;
use symphonia::core::errors::Error as SymphoniaError;
use symphonia::core::formats::probe::Hint;
use symphonia::core::formats::{FormatOptions, TrackType};
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;

use crate::frb_generated::StreamSink;

use super::{logger::log_to_dart, tag_reader::write_replay_gain_tags};

const REPLAY_GAIN_REFERENCE_LUFS: f64 = -18.0;

pub enum ReplayGainScanMode {
    Album,
    Track,
}

pub struct ReplayGainProgress {
    pub completed: u64,
    pub total: u64,
    pub message: String,
    pub failed: u64,
}

struct LoudnessResult {
    analyzer: EbuR128,
    channels: u32,
}

pub fn write_replay_gain(
    paths: Vec<String>,
    mode: ReplayGainScanMode,
    sink: StreamSink<ReplayGainProgress>,
) -> Result<(), String> {
    if paths.is_empty() {
        return Err("没有可处理的歌曲".to_string());
    }
    let total = paths.len() as u64;
    log_to_dart(format!(
        "[replay gain] start mode={} total={total}",
        mode_name(&mode)
    ));
    match mode {
        ReplayGainScanMode::Track => write_track_gain(paths, total, sink),
        ReplayGainScanMode::Album => write_album_gain(paths, total, sink),
    }
}

fn write_track_gain(
    paths: Vec<String>,
    total: u64,
    sink: StreamSink<ReplayGainProgress>,
) -> Result<(), String> {
    let mut failed = 0;
    for (index, path) in paths.iter().enumerate() {
        let completed = index as u64;
        log_to_dart(format!(
            "[replay gain] track scan {}/{} file={}",
            completed + 1,
            total,
            display_name(path)
        ));
        let _ = sink.add(ReplayGainProgress {
            completed,
            total,
            message: format!("正在分析 {}", display_name(path)),
            failed,
        });
        match analyze_file(path).and_then(|result| values_from_result(&result)) {
            Ok((gain, peak)) => {
                if let Err(error) = write_replay_gain_tags(path, Some((&gain, &peak)), None) {
                    failed += 1;
                    log_to_dart(format!(
                        "[replay gain] track write failed file={} error={error}",
                        display_name(path)
                    ));
                    let _ = sink.add(ReplayGainProgress {
                        completed,
                        total,
                        message: format!("写入失败：{} ({error})", display_name(path)),
                        failed,
                    });
                } else {
                    log_to_dart(format!(
                        "[replay gain] track written file={} gain={gain} peak={peak}",
                        display_name(path)
                    ));
                }
            }
            Err(error) => {
                failed += 1;
                log_to_dart(format!(
                    "[replay gain] track scan failed file={} error={error}",
                    display_name(path)
                ));
                let _ = sink.add(ReplayGainProgress {
                    completed,
                    total,
                    message: format!("分析失败：{} ({error})", display_name(path)),
                    failed,
                });
            }
        }
        let _ = sink.add(ReplayGainProgress {
            completed: completed + 1,
            total,
            message: "正在写入音轨增益标签…".to_string(),
            failed,
        });
    }
    log_to_dart(format!(
        "[replay gain] completed mode=track total={total} failed={failed}"
    ));
    Ok(())
}

fn write_album_gain(
    paths: Vec<String>,
    total: u64,
    sink: StreamSink<ReplayGainProgress>,
) -> Result<(), String> {
    let mut analyses = Vec::with_capacity(paths.len());
    for (index, path) in paths.iter().enumerate() {
        log_to_dart(format!(
            "[replay gain] album scan {}/{} file={}",
            index + 1,
            total,
            display_name(path)
        ));
        let _ = sink.add(ReplayGainProgress {
            completed: index as u64,
            total,
            message: format!("正在分析 {}", display_name(path)),
            failed: 0,
        });
        let analysis = analyze_file(path).map_err(|error| {
            let message = format!(
                "无法完成专辑分析，未写入任何标签：{} ({error})",
                display_name(path)
            );
            log_to_dart(format!("[replay gain] album scan failed error={message}"));
            message
        })?;
        analyses.push(analysis);
        let _ = sink.add(ReplayGainProgress {
            completed: index as u64 + 1,
            total,
            message: "正在分析专辑响度…".to_string(),
            failed: 0,
        });
    }

    let loudness = EbuR128::loudness_global_multiple(
        analyses.iter().map(|result| &result.analyzer),
    )
    .map_err(|error| {
        let message = format!("无法计算专辑响度：{error}");
        log_to_dart(format!(
            "[replay gain] album calculation failed error={message}"
        ));
        message
    })?;
    if !loudness.is_finite() {
        return Err("无法计算专辑响度".to_string());
    }
    let peak = analyses
        .iter()
        .map(peak_from_result)
        .collect::<Result<Vec<_>, _>>()?
        .into_iter()
        .fold(0.0_f64, f64::max);
    let gain = format_gain(REPLAY_GAIN_REFERENCE_LUFS - loudness);
    let peak = format_peak(peak);
    log_to_dart(format!(
        "[replay gain] album analyzed loudness={loudness:.2} gain={gain} peak={peak}"
    ));

    for (index, path) in paths.iter().enumerate() {
        let completed = index as u64;
        log_to_dart(format!(
            "[replay gain] album write {}/{} file={}",
            completed + 1,
            total,
            display_name(path)
        ));
        let _ = sink.add(ReplayGainProgress {
            completed,
            total,
            message: format!("正在写入 {}", display_name(path)),
            failed: 0,
        });
        write_replay_gain_tags(path, None, Some((&gain, &peak))).map_err(|error| {
            let message = format!(
                "写入专辑增益失败，已完成 {completed}/{total} 首：{} ({error})",
                display_name(path)
            );
            log_to_dart(format!("[replay gain] album write failed error={message}"));
            message
        })?;
        log_to_dart(format!(
            "[replay gain] album written file={} gain={gain} peak={peak}",
            display_name(path)
        ));
        let _ = sink.add(ReplayGainProgress {
            completed: completed + 1,
            total,
            message: "正在写入专辑增益标签…".to_string(),
            failed: 0,
        });
    }
    log_to_dart(format!(
        "[replay gain] completed mode=album total={total} failed=0"
    ));
    Ok(())
}

fn analyze_file(path: &str) -> Result<LoudnessResult, String> {
    let source = File::open(path).map_err(|error| format!("无法打开音频文件：{error}"))?;
    let media_source = MediaSourceStream::new(Box::new(source), Default::default());
    let mut hint = Hint::new();
    if let Some(extension) = Path::new(path).extension().and_then(|value| value.to_str()) {
        hint.with_extension(extension);
    }
    let mut format = symphonia::default::get_probe()
        .probe(
            &hint,
            media_source,
            FormatOptions::default(),
            MetadataOptions::default(),
        )
        .map_err(|error| format!("不支持的音频格式：{error}"))?;
    let track = format
        .default_track(TrackType::Audio)
        .ok_or_else(|| "未找到音频轨道".to_string())?;
    let parameters = track
        .codec_params
        .as_ref()
        .and_then(|parameters| parameters.audio())
        .ok_or_else(|| "缺少音频解码参数".to_string())?;
    let track_id = track.id;
    let mut decoder = symphonia::default::get_codecs()
        .make_audio_decoder(parameters, &AudioDecoderOptions::default())
        .map_err(|error| format!("不支持的音频编码：{error}"))?;
    let mut analyzer: Option<EbuR128> = None;
    let mut channels = 0;
    let mut decoded = Vec::<f32>::new();

    loop {
        let packet = match format.next_packet() {
            Ok(Some(packet)) => packet,
            Ok(None) => break,
            Err(SymphoniaError::ResetRequired) => {
                return Err("音频轨道在扫描期间发生变化".to_string());
            }
            Err(SymphoniaError::IoError(error))
                if error.kind() == std::io::ErrorKind::UnexpectedEof =>
            {
                break;
            }
            Err(error) => return Err(format!("读取音频失败：{error}")),
        };
        if packet.track_id != track_id {
            continue;
        }
        let audio = match decoder.decode(&packet) {
            Ok(audio) => audio,
            Err(SymphoniaError::DecodeError(_)) | Err(SymphoniaError::IoError(_)) => continue,
            Err(error) => return Err(format!("解码音频失败：{error}")),
        };
        let packet_channels = audio.spec().channels().count() as u32;
        let rate = audio.spec().rate();
        if packet_channels == 0 || rate == 0 {
            return Err("音频采样参数无效".to_string());
        }
        match analyzer.as_mut() {
            Some(analyzer) if analyzer.channels() == packet_channels && analyzer.rate() == rate => {
            }
            Some(_) => return Err("音频轨道的采样参数发生变化".to_string()),
            None => {
                channels = packet_channels;
                analyzer = Some(
                    EbuR128::new(packet_channels, rate, Mode::I | Mode::SAMPLE_PEAK)
                        .map_err(|error| format!("无法初始化响度分析器：{error}"))?,
                );
            }
        }
        decoded.resize(audio.samples_interleaved(), f32::MID);
        audio.copy_to_slice_interleaved(&mut decoded);
        analyzer
            .as_mut()
            .expect("analyzer initialized after valid packet")
            .add_frames_f32(&decoded)
            .map_err(|error| format!("无法分析音频响度：{error}"))?;
    }

    let analyzer = analyzer.ok_or_else(|| "音频文件没有可分析的样本".to_string())?;
    Ok(LoudnessResult { analyzer, channels })
}

fn values_from_result(result: &LoudnessResult) -> Result<(String, String), String> {
    let loudness = result
        .analyzer
        .loudness_global()
        .map_err(|error| format!("无法计算音轨响度：{error}"))?;
    if !loudness.is_finite() {
        return Err("无法计算音轨响度".to_string());
    }
    Ok((
        format_gain(REPLAY_GAIN_REFERENCE_LUFS - loudness),
        format_peak(peak_from_result(result)?),
    ))
}

fn peak_from_result(result: &LoudnessResult) -> Result<f64, String> {
    (0..result.channels)
        .map(|channel| {
            result
                .analyzer
                .sample_peak(channel)
                .map_err(|error| format!("无法计算音频峰值：{error}"))
        })
        .collect::<Result<Vec<_>, _>>()
        .map(|peaks| peaks.into_iter().fold(0.0_f64, f64::max))
}

fn format_gain(gain: f64) -> String {
    format!("{gain:.2} dB")
}

fn format_peak(peak: f64) -> String {
    format!("{peak:.6}")
}

fn display_name(path: &str) -> String {
    Path::new(path)
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or(path)
        .to_string()
}

fn mode_name(mode: &ReplayGainScanMode) -> &'static str {
    match mode {
        ReplayGainScanMode::Album => "album",
        ReplayGainScanMode::Track => "track",
    }
}
