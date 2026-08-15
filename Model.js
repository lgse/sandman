.pragma library

var screensaverPresets = [60, 120, 300, 600, 900, 1800]
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
    screensaver: normalizedSeconds(parsed.screensaver, 150, false),
    sleep: normalizedSeconds(parsed.sleep, 0, true)
  }
}

function formatDuration(seconds) {
  var value = Number(seconds)
  if (!isFinite(value) || value <= 0) return "Off"
  if (value < 60) return Math.round(value) + " sec"

  var minutes = Math.round(value / 60)
  if (minutes < 60) return minutes + " min"

  var hours = minutes / 60
  return (hours === Math.round(hours) ? String(Math.round(hours)) : hours.toFixed(1)) + (hours === 1 ? " hour" : " hours")
}

function statusSummary(screensaver, sleep) {
  return "Screen " + formatDuration(screensaver) + " · Sleep " + formatDuration(sleep)
}
