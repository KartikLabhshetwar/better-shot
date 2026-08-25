"use client"

import { useCallback, useEffect, useRef, useState } from "react"

export const PLAYBACK_RATES = [0.5, 0.75, 1, 1.25, 1.5, 2] as const

const CONTROLS_IDLE_MS = 2600
const VOLUME_STORAGE_KEY = "bettershot_share_volume"

export interface PlayerState {
  ready: boolean
  playing: boolean
  ended: boolean
  waiting: boolean
  currentTime: number
  duration: number
  buffered: number
  volume: number
  muted: boolean
  rate: number
  fullscreen: boolean
  pip: boolean
  failed: boolean
}

const INITIAL_STATE: PlayerState = {
  ready: false,
  playing: false,
  ended: false,
  waiting: false,
  currentTime: 0,
  duration: 0,
  buffered: 0,
  volume: 1,
  muted: false,
  rate: 1,
  fullscreen: false,
  pip: false,
  failed: false,
}

function readStoredVolume(): { volume: number; muted: boolean } | null {
  try {
    const raw = window.localStorage.getItem(VOLUME_STORAGE_KEY)
    if (!raw) return null
    const parsed = JSON.parse(raw) as { volume?: number; muted?: boolean }
    if (typeof parsed.volume !== "number" || Number.isNaN(parsed.volume)) return null
    return { volume: Math.min(1, Math.max(0, parsed.volume)), muted: Boolean(parsed.muted) }
  } catch {
    return null
  }
}

function persistVolume(volume: number, muted: boolean) {
  try {
    window.localStorage.setItem(VOLUME_STORAGE_KEY, JSON.stringify({ volume, muted }))
  } catch {
    /* storage unavailable */
  }
}

export function usePlayer(shellRef: React.RefObject<HTMLElement | null>) {
  const videoRef = useRef<HTMLVideoElement | null>(null)
  const [state, setState] = useState<PlayerState>(INITIAL_STATE)
  const [controlsVisible, setControlsVisible] = useState(true)
  const [scrubbing, setScrubbing] = useState(false)
  const idleTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const scrubbingRef = useRef(false)

  scrubbingRef.current = scrubbing

  const patch = useCallback((next: Partial<PlayerState>) => {
    setState((prev) => ({ ...prev, ...next }))
  }, [])

  const revealControls = useCallback(() => {
    setControlsVisible(true)
    if (idleTimer.current) clearTimeout(idleTimer.current)
    idleTimer.current = setTimeout(() => {
      const video = videoRef.current
      if (!video || video.paused || scrubbingRef.current) return
      setControlsVisible(false)
    }, CONTROLS_IDLE_MS)
  }, [])

  useEffect(() => {
    const video = videoRef.current
    if (!video) return

    const stored = readStoredVolume()
    if (stored) {
      video.volume = stored.volume
      video.muted = stored.muted
    }

    const syncBuffered = () => {
      if (!video.buffered.length || !video.duration) return 0
      let furthest = 0
      for (let i = 0; i < video.buffered.length; i += 1) {
        if (video.buffered.start(i) <= video.currentTime) {
          furthest = Math.max(furthest, video.buffered.end(i))
        }
      }
      return furthest
    }

    const onLoadedMetadata = () =>
      patch({
        ready: true,
        duration: Number.isFinite(video.duration) ? video.duration : 0,
        volume: video.volume,
        muted: video.muted,
      })
    const onTimeUpdate = () => {
      if (scrubbingRef.current) return
      patch({ currentTime: video.currentTime, buffered: syncBuffered() })
    }
    const onProgress = () => patch({ buffered: syncBuffered() })
    const onPlay = () => {
      patch({ playing: true, ended: false })
      revealControls()
    }
    const onPause = () => {
      patch({ playing: false })
      setControlsVisible(true)
    }
    const onEnded = () => {
      patch({ playing: false, ended: true })
      setControlsVisible(true)
    }
    const onWaiting = () => patch({ waiting: true })
    const onPlaying = () => patch({ waiting: false })
    const onVolumeChange = () => {
      patch({ volume: video.volume, muted: video.muted })
      persistVolume(video.volume, video.muted)
    }
    const onRateChange = () => patch({ rate: video.playbackRate })
    const onError = () => patch({ failed: true, waiting: false })
    const onEnterPip = () => patch({ pip: true })
    const onLeavePip = () => patch({ pip: false })

    video.addEventListener("loadedmetadata", onLoadedMetadata)
    video.addEventListener("timeupdate", onTimeUpdate)
    video.addEventListener("progress", onProgress)
    video.addEventListener("play", onPlay)
    video.addEventListener("pause", onPause)
    video.addEventListener("ended", onEnded)
    video.addEventListener("waiting", onWaiting)
    video.addEventListener("playing", onPlaying)
    video.addEventListener("volumechange", onVolumeChange)
    video.addEventListener("ratechange", onRateChange)
    video.addEventListener("error", onError)
    video.addEventListener("enterpictureinpicture", onEnterPip)
    video.addEventListener("leavepictureinpicture", onLeavePip)

    if (video.readyState >= 1) onLoadedMetadata()

    return () => {
      video.removeEventListener("loadedmetadata", onLoadedMetadata)
      video.removeEventListener("timeupdate", onTimeUpdate)
      video.removeEventListener("progress", onProgress)
      video.removeEventListener("play", onPlay)
      video.removeEventListener("pause", onPause)
      video.removeEventListener("ended", onEnded)
      video.removeEventListener("waiting", onWaiting)
      video.removeEventListener("playing", onPlaying)
      video.removeEventListener("volumechange", onVolumeChange)
      video.removeEventListener("ratechange", onRateChange)
      video.removeEventListener("error", onError)
      video.removeEventListener("enterpictureinpicture", onEnterPip)
      video.removeEventListener("leavepictureinpicture", onLeavePip)
    }
  }, [patch, revealControls])

  useEffect(() => {
    const onFullscreenChange = () =>
      patch({ fullscreen: document.fullscreenElement === shellRef.current })
    document.addEventListener("fullscreenchange", onFullscreenChange)
    return () => document.removeEventListener("fullscreenchange", onFullscreenChange)
  }, [patch, shellRef])

  useEffect(
    () => () => {
      if (idleTimer.current) clearTimeout(idleTimer.current)
    },
    []
  )

  const play = useCallback(() => {
    videoRef.current?.play().catch(() => patch({ playing: false }))
  }, [patch])

  const pause = useCallback(() => {
    videoRef.current?.pause()
  }, [])

  const toggle = useCallback(() => {
    const video = videoRef.current
    if (!video) return
    if (video.paused) play()
    else pause()
    revealControls()
  }, [pause, play, revealControls])

  const seek = useCallback(
    (time: number) => {
      const video = videoRef.current
      if (!video || !Number.isFinite(video.duration)) return
      const clamped = Math.min(Math.max(0, time), video.duration)
      video.currentTime = clamped
      patch({ currentTime: clamped, ended: false })
    },
    [patch]
  )

  const skip = useCallback(
    (delta: number) => {
      const video = videoRef.current
      if (!video) return
      seek(video.currentTime + delta)
      revealControls()
    },
    [revealControls, seek]
  )

  const setVolume = useCallback((volume: number) => {
    const video = videoRef.current
    if (!video) return
    const clamped = Math.min(1, Math.max(0, volume))
    video.volume = clamped
    video.muted = clamped === 0
  }, [])

  const toggleMute = useCallback(() => {
    const video = videoRef.current
    if (!video) return
    if (video.muted && video.volume === 0) video.volume = 0.6
    video.muted = !video.muted
  }, [])

  const setRate = useCallback((rate: number) => {
    const video = videoRef.current
    if (!video) return
    video.playbackRate = rate
  }, [])

  const toggleFullscreen = useCallback(() => {
    const shell = shellRef.current
    if (!shell) return
    if (document.fullscreenElement === shell) document.exitFullscreen().catch(() => {})
    else shell.requestFullscreen?.().catch(() => {})
  }, [shellRef])

  const togglePip = useCallback(async () => {
    const video = videoRef.current
    if (!video || !document.pictureInPictureEnabled) return
    try {
      if (document.pictureInPictureElement === video) await document.exitPictureInPicture()
      else await video.requestPictureInPicture()
    } catch {
      /* denied by the browser */
    }
  }, [])

  const beginScrub = useCallback(() => {
    setScrubbing(true)
    setControlsVisible(true)
  }, [])

  const endScrub = useCallback(() => {
    setScrubbing(false)
    revealControls()
  }, [revealControls])

  return {
    videoRef,
    state,
    controlsVisible: controlsVisible || !state.playing || scrubbing,
    scrubbing,
    revealControls,
    play,
    pause,
    toggle,
    seek,
    skip,
    setVolume,
    toggleMute,
    setRate,
    toggleFullscreen,
    togglePip,
    beginScrub,
    endScrub,
  }
}

export type PlayerApi = ReturnType<typeof usePlayer>
