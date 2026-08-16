.pragma library

var screensaverPresets = [0, 60, 120, 300, 600, 900, 1800]
var lockPresets = [0, 300, 600, 900, 1800, 3600]
var sleepPresets = [0, 900, 1800, 3600, 7200]

var maxTimeoutSeconds = 7 * 24 * 60 * 60

// Validate a caller-supplied timeout, including one arriving over IPC.
// Returns whole seconds in [0, maxTimeoutSeconds], or -1 when the value is
// unusable. Callers must treat -1 as "reject" and never as 0: coercing a bad
// value to 0 would read as "Off" and stand auto-lock down.
//
// Out-of-range values are rejected rather than clamped, matching the CLI. A
// clamp would turn an absurd setLock into a seven-day timeout, which is the
// same silent weakening this is meant to prevent.
function requestedSeconds(value) {
  var number = Number(value)
  if (!isFinite(number)) return -1
  number = Math.round(number)
  if (number < 0 || number > maxTimeoutSeconds) return -1
  return number
}

// Normalize a value already on disk. Unlike requestedSeconds there is no caller
// to report back to, so an oversized value is clamped rather than rejected -
// the bound is what keeps sleepDelaySeconds * 1000 inside a 32-bit int.
function normalizedSeconds(value, fallback, allowOff) {
  var number = Number(value)
  if (!isFinite(number)) return fallback
  number = Math.round(number)
  if (allowOff && number === 0) return 0
  if (number <= 0) return fallback
  return Math.min(number, maxTimeoutSeconds)
}

function parseConfig(raw) {
  var parsed = {}
  try { parsed = JSON.parse(String(raw || "{}")) }
  catch (error) { parsed = {} }

  return {
    screensaver: normalizedSeconds(parsed.screensaver, 150, true),
    lock: normalizedSeconds(parsed.lock, 300, true),
    sleep: normalizedSeconds(parsed.sleep, 0, true)
  }
}

function formatDuration(seconds) {
  var value = Number(seconds)
  if (!isFinite(value) || value <= 0) return "Off"
  if (value < 60) return Math.round(value) + " sec"

  var minutes = value / 60
  if (minutes < 60) {
    var minuteLabel = minutes === Math.round(minutes)
      ? String(Math.round(minutes)) : minutes.toFixed(1).replace(/\.0$/, "")
    return minuteLabel + " min"
  }

  var hours = minutes / 60
  return (hours === Math.round(hours) ? String(Math.round(hours)) : hours.toFixed(1)) + (hours === 1 ? " hour" : " hours")
}

function isPreset(value, presets) {
  var seconds = Number(value)
  for (var i = 0; i < presets.length; i++) {
    if (seconds === Number(presets[i])) return true
  }
  return false
}

function customParts(seconds) {
  var totalMinutes = Math.max(1, Math.round(Number(seconds) / 60))
  return {
    hours: Math.floor(totalMinutes / 60),
    minutes: totalMinutes % 60
  }
}

function customSeconds(hours, minutes) {
  var safeHours = Math.max(0, Math.min(24, Math.round(Number(hours) || 0)))
  var safeMinutes = Math.max(0, Math.min(59, Math.round(Number(minutes) || 0)))
  return (safeHours * 60 + safeMinutes) * 60
}

function statusSummary(screensaver, lock, sleep) {
  return "Screen " + formatDuration(screensaver)
    + " · Lock " + formatDuration(lock)
    + " · Sleep " + formatDuration(sleep)
}
