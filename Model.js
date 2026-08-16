.pragma library

var screensaverPresets = [0, 60, 120, 300, 600, 900, 1800]
var displayPresets = [0, 60, 120, 300, 600, 900, 1800]
var lockPresets = [0, 300, 600, 900, 1800, 3600]
var sleepPresets = [0, 900, 1800, 3600, 7200]

function normalizedSeconds(value, fallback, allowOff) {
  var number = Number(value)
  if (!isFinite(number)) return fallback
  number = Math.round(number)
  if (allowOff && number === 0) return 0
  return number > 0 ? number : fallback
}

function parseConfig(raw) {
  var parsed = {}
  try { parsed = JSON.parse(String(raw || "{}")) }
  catch (error) { parsed = {} }

  return {
    screensaver: normalizedSeconds(parsed.screensaver, 150, true),
    display: normalizedSeconds(parsed.display, 0, true),
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

function statusSummary(screensaver, display, lock, sleep) {
  return "Screen " + formatDuration(screensaver)
    + " · Displays " + formatDuration(display)
    + " · Lock " + formatDuration(lock)
    + " · Sleep " + formatDuration(sleep)
}
