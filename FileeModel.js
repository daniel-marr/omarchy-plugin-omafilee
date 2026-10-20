.pragma library

// Pure logic for the donut converter: catalogue parsing, Filee's toolbar
// profiles, slice geometry and result parsing. Kept free of QML so tests/run
// can exercise it under Node.

var MAX_SLICES = 12
var MAX_TEXT = 4000

// Filee's factory donuts (src/Filee.Core/Presets/BuiltInData.cs), keyed by the
// category names `filee formats` prints. Clockwise from 12 o'clock.
// Copyright (c) 2026 Myeonggu Kim (KnifeLemon) and Filee contributors, MIT;
// see NOTICE.md.
var DEFAULT_PROFILES = [
  { id: "images", categories: ["Image"],
    presetIds: ["to-png", "to-jpg", "to-webp", "to-pdf", "trace-svg", "trace-line-art", "to-tiff", "to-bmp", "to-ico", "half-size"] },
  { id: "pdf", categories: ["Pdf"],
    presetIds: ["to-png", "to-jpg", "pdf-long-image", "to-docx", "pdf-slides", "to-txt", "to-md", "to-epub", "to-hwpx", "to-hwp", "pdf-split", "merge-pdf"] },
  { id: "office", categories: ["Document"],
    presetIds: ["to-pdf", "to-hwpx", "to-hwp", "to-docx", "to-odt", "to-txt", "to-html", "to-epub", "to-png", "merge-pdf"] },
  { id: "spreadsheets", categories: ["Spreadsheet"],
    presetIds: ["to-pdf", "to-xlsx", "to-csv", "to-json", "to-ods", "to-hwpx", "to-hwp", "to-html", "merge-pdf"] },
  { id: "presentations", categories: ["Presentation"],
    presetIds: ["to-pdf", "to-png", "to-jpg", "to-pptx", "to-hwpx", "to-hwp", "merge-pdf"] },
  { id: "hwp", categories: ["Hwp"],
    presetIds: ["to-pdf", "to-docx", "to-hwpx", "to-hwp", "to-png", "to-jpg", "to-txt", "to-md", "to-epub", "merge-pdf"] },
  { id: "text", categories: ["Text"],
    presetIds: ["to-pdf", "to-hwpx", "to-hwp", "to-docx", "to-html", "to-txt", "to-epub"] },
  { id: "ebooks", categories: ["Ebook"],
    presetIds: ["to-pdf", "to-epub", "to-docx", "to-txt", "to-azw3", "to-mobi", "to-kepub", "to-hwpx", "to-hwp", "to-html"] },
  { id: "video", categories: ["Video"],
    presetIds: ["to-mp4", "mp4-720", "mp4-hevc", "to-webm", "to-mov", "to-gif", "to-mp3", "extract-subtitles", "to-mkv", "to-avi"] },
  { id: "audio", categories: ["Audio"],
    presetIds: ["to-mp3", "mp3-128", "to-m4a", "to-wav", "to-flac", "to-ogg", "to-opus", "to-aac"] },
  { id: "subtitles", categories: ["Subtitle"],
    presetIds: ["to-srt", "to-vtt", "to-ass", "to-smi", "to-lrc", "to-ttml"] },
  { id: "vector", categories: ["Vector"],
    presetIds: ["to-png", "to-pdf", "to-svg", "to-jpg", "to-webp", "to-eps"] },
  { id: "archives", categories: ["Archive"],
    presetIds: ["extract", "to-zip", "to-7z", "to-tgz", "to-tar"] },
  { id: "cad", categories: ["Cad"],
    presetIds: ["to-pdf", "to-png", "to-svg", "to-dxf", "to-dwg"] },
  { id: "fonts", categories: ["Font"],
    presetIds: ["to-woff2", "to-woff", "to-ttf", "to-otf", "to-eot"] },
  { id: "data", categories: ["Data"],
    presetIds: ["to-json", "to-yaml", "to-toml", "to-xml", "to-csv", "to-xlsx"] },
  { id: "models", categories: ["Model3D"],
    presetIds: ["to-glb", "to-stl", "to-obj", "to-3mf", "to-ply", "to-png"] },
  { id: "mixed", fallback: true,
    presetIds: ["to-pdf", "merge-pdf", "zip-all", "to-png", "to-txt"] }
]

function splitColumns(line) {
  return String(line).trim().split(/\s{2,}/)
}

// `filee formats`: "Image:" headers followed by "  png   PNG  .png" rows.
function parseFormats(text) {
  var formats = ({})
  var extMap = ({})
  var order = []
  var category = ""
  String(text || "").split("\n").forEach(function(line) {
    var header = line.match(/^(\S[^:]*):\s*$/)
    if (header) { category = header[1]; return }
    if (!/^\s+\S/.test(line) || category === "") return
    var cols = splitColumns(line)
    if (cols.length < 3) return
    var id = cols[0].toLowerCase()
    var exts = cols.slice(2).join(" ").split(/\s+/)
      .filter(function(e) { return e.charAt(0) === "." })
      .map(function(e) { return e.slice(1).toLowerCase() })
    formats[id] = { id: id, name: cols[1], category: category, exts: exts }
    order.push(id)
    exts.forEach(function(e) { if (!(e in extMap)) extMap[e] = id })
    if (!(id in extMap)) extMap[id] = id
  })
  return { formats: formats, extMap: extMap, order: order }
}

// `filee presets`: an ID / NAME / TARGET table.
function parsePresets(text) {
  var list = []
  String(text || "").split("\n").forEach(function(line) {
    if (line.trim() === "" || /^ID\s{2,}/.test(line) || /^Use one with/.test(line)) return
    var cols = splitColumns(line)
    if (cols.length < 3) return
    list.push({ id: cols[0], name: cols[1], target: cols[cols.length - 1] })
  })
  return list
}

// The user's own donuts from the Filee app (~/.config/Filee/profiles.json),
// or null when absent/unreadable so the factory donuts apply.
function parseUserProfiles(text) {
  var data
  try { data = JSON.parse(String(text || "")) } catch (e) { return null }
  if (data && !Array.isArray(data) && Array.isArray(data.profiles)) data = data.profiles
  if (!Array.isArray(data)) return null
  var list = data.filter(function(p) { return p && Array.isArray(p.presetIds) }).map(function(p) {
    return {
      id: String(p.id || ""),
      extensions: (Array.isArray(p.extensions) ? p.extensions : []).map(function(e) { return String(e).replace(/^\./, "").toLowerCase() }),
      fallback: p.isFallback === true,
      presetIds: p.presetIds.filter(function(id) { return typeof id === "string" }).slice(0, MAX_SLICES)
    }
  })
  return list.length > 0 ? list : null
}

function extensionOf(path) {
  var name = basename(path).toLowerCase()
  var dot = name.lastIndexOf(".")
  return dot > 0 ? name.slice(dot + 1) : ""
}

// Filee's ProfileSelector: first normal profile holding every extension,
// then the first mixed profile whose extensions cover them, then the catch-all.
function selectUserProfile(profiles, files) {
  var exts = []
  files.forEach(function(f) { var e = extensionOf(f.path); if (exts.indexOf(e) < 0) exts.push(e) })
  function covers(p) { return exts.every(function(e) { return p.extensions.indexOf(e) >= 0 }) }
  var match = null
  if (exts.length > 0) {
    match = profiles.find(function(p) { return !p.fallback && covers(p) })
      || profiles.find(function(p) { return p.fallback && p.extensions.length > 0 && covers(p) })
  }
  return match
    || profiles.find(function(p) { return p.fallback && p.extensions.length === 0 })
    || profiles.find(function(p) { return p.fallback })
    || profiles[0] || null
}

// Same rule over the factory donuts, using the catalogue's categories.
function selectDefaultProfile(files, formats) {
  var cats = []
  files.forEach(function(f) {
    var fmt = formats[f.format]
    var cat = fmt ? fmt.category : ""
    if (cats.indexOf(cat) < 0) cats.push(cat)
  })
  if (cats.length === 1 && cats[0] !== "") {
    var match = DEFAULT_PROFILES.find(function(p) { return p.categories && p.categories.indexOf(cats[0]) >= 0 })
    if (match) return match
  }
  return DEFAULT_PROFILES[DEFAULT_PROFILES.length - 1]
}

// Slices for a profile, dropping preset ids this Filee doesn't know.
function slicesFor(profile, presets) {
  if (!profile) return []
  var byId = ({})
  presets.forEach(function(p) { byId[p.id] = p })
  return profile.presetIds
    .filter(function(id) { return id in byId })
    .slice(0, MAX_SLICES)
    .map(function(id) { return { id: id, name: byId[id].name, target: byId[id].target } })
}

// ---------------------------------------------------------- geometry

// Angles are clockwise from 12 o'clock in radians; slice i is centred on i·span.
function span(count) {
  return count <= 0 ? 2 * Math.PI : 2 * Math.PI / count
}

function angleOf(cx, cy, x, y) {
  var a = Math.atan2(x - cx, cy - y)
  return a < 0 ? a + 2 * Math.PI : a
}

// { kind: "outside" | "center" | "ring" | "slice", index }
function hitTest(cx, cy, x, y, inner, outer, count, slack) {
  var d = Math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy))
  if (d < inner) return { kind: "center", index: -1 }
  if (d > outer + (slack || 0)) return { kind: "outside", index: -1 }
  if (count <= 0) return { kind: "ring", index: -1 }
  var s = span(count)
  return { kind: "slice", index: Math.floor((angleOf(cx, cy, x, y) + s / 2) / s) % count }
}

// Point at a clockwise-from-top angle, for placing labels.
function pointAt(cx, cy, radius, angle) {
  return { x: cx + radius * Math.sin(angle), y: cy - radius * Math.cos(angle) }
}

// ---------------------------------------------------------- files

function basename(path) {
  var s = String(path || "").replace(/\/+$/, "")
  return s.slice(s.lastIndexOf("/") + 1)
}

function dirname(path) {
  var s = String(path || "")
  var i = s.lastIndexOf("/")
  return i <= 0 ? "/" : s.slice(0, i)
}

function urlToPath(url) {
  var s = String(url || "")
  if (s.indexOf("file://") !== 0) return s.charAt(0) === "/" ? s : ""
  s = s.slice(7)
  if (s.charAt(0) !== "/") s = s.slice(s.indexOf("/"))
  try { return decodeURIComponent(s) } catch (e) { return "" }
}

// "archive.tar.gz" should resolve to tar.gz before gz.
function formatForPath(path, extMap) {
  var name = basename(path).toLowerCase()
  var parts = name.split(".")
  for (var n = Math.min(3, parts.length - 1); n >= 1; n--) {
    var ext = parts.slice(parts.length - n).join(".")
    if (extMap && ext in extMap) return extMap[ext]
  }
  return ""
}

// Absolute, de-duplicated paths as file records.
function toFiles(paths, extMap) {
  var seen = ({})
  var out = []
  paths.forEach(function(p) {
    var path = String(p || "").trim()
    if (path.charAt(0) !== "/" || seen[path]) return
    seen[path] = true
    out.push({ path: path, name: basename(path), format: formatForPath(path, extMap) })
  })
  return out
}

// Filee's CLI expands any input containing * or ? as a wildcard and has no
// way to escape it, so such a path could convert other files in its folder.
function isLiteralPath(path) {
  return !/[*?]/.test(String(path || ""))
}

function convertArgs(files, presetId) {
  var args = ["convert"]
  files.forEach(function(f) { if (f.format !== "" && isLiteralPath(f.path)) args.push(f.path) })
  args.push("--preset", presetId, "--json")
  return args
}

function cap(text) {
  var s = String(text || "")
  return s.length > MAX_TEXT ? s.slice(0, MAX_TEXT) + "…" : s
}

// Parses `filee convert --json`; returns { ok, files[], error }.
function parseResult(text) {
  var data
  try { data = JSON.parse(String(text || "")) }
  catch (e) { return { ok: false, files: [], error: "Filee returned no result" } }
  if (!data || !Array.isArray(data.files)) return { ok: false, files: [], error: "Unexpected output from Filee" }
  var files = data.files.slice(0, 500).map(function(f) {
    var outputs = Array.isArray(f.outputs) ? f.outputs.filter(function(o) { return typeof o === "string" }) : []
    return {
      source: String(f.source || ""),
      state: String(f.state || ""),
      outputs: outputs,
      error: cap(f.error || f.notice || "")
    }
  })
  return { ok: true, files: files, error: "" }
}

// One-line summary for the donut's centre after a run.
function summarize(result) {
  var done = result.files.filter(function(f) { return f.state === "done" })
  var failed = result.files.filter(function(f) { return f.state !== "done" && f.state !== "skipped" })
  var outputs = []
  done.forEach(function(f) { outputs = outputs.concat(f.outputs) })
  var firstError = failed.length > 0 ? (failed[0].error || failed[0].state) : ""
  return {
    ok: failed.length === 0 && done.length > 0,
    done: done.length,
    failed: failed.length,
    outputs: outputs,
    error: firstError,
    failedSources: failed.map(function(f) { return f.source })
  }
}
