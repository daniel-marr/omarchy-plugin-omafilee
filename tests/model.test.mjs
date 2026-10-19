// Unit tests for FileeModel.js, run under Node: node --test tests/
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'

const source = readFileSync(new URL('../FileeModel.js', import.meta.url), 'utf8').replace(/^\.pragma library\s*$/m, '')
const Model = {}
vm.runInNewContext(source + `
Object.assign(out, { DEFAULT_PROFILES, parseFormats, parsePresets, parseUserProfiles, selectUserProfile,
  selectDefaultProfile, slicesFor, hitTest, urlToPath, formatForPath, toFiles, convertArgs, parseResult, summarize })`,
{ out: Model })
const plain = v => JSON.parse(JSON.stringify(v))

const formatsText = `Image:
  png        PNG  .png
  jpg        JPG  .jpg .jpeg .jpe .jfif
  jxl        JPEG XL  .jxl
Pdf:
  pdf        PDF  .pdf
Archive:
  tar.gz     TAR.GZ  .tar.gz .tgz
  gz         GZ  .gz
`
const presetsText = `ID                       NAME                         TARGET
to-png                   PNG                          png
to-jpg                   JPG                          jpg
to-pdf                   PDF                          pdf
merge-pdf                Merge PDF                    pdf
half-size                Half size                    *
zip-all                  One ZIP                      zip

Use one with: filee convert <files> --preset <id or name>
`
const { formats, extMap } = Model.parseFormats(formatsText)
const presets = Model.parsePresets(presetsText)

test('parseFormats reads categories, multi-word names and extensions', () => {
  assert.equal(formats.jxl.name, 'JPEG XL')
  assert.equal(formats.jpg.category, 'Image')
  assert.equal(extMap.jpeg, 'jpg')
})

test('parsePresets skips the header and footer', () => {
  assert.equal(presets.length, 6)
  assert.equal(presets[3].name, 'Merge PDF')
})

test('formatForPath prefers the longest extension', () => {
  assert.equal(Model.formatForPath('/x/a.TAR.GZ', extMap), 'tar.gz')
  assert.equal(Model.formatForPath('/x/a.gz', extMap), 'gz')
  assert.equal(Model.formatForPath('/x/README', extMap), '')
})

test('toFiles dedupes and drops relative paths', () => {
  const files = Model.toFiles(['/a/x.png', '/a/x.png', 'rel.png', '-rf'], extMap)
  assert.deepEqual(plain(files), [{ path: '/a/x.png', name: 'x.png', format: 'png' }])
})

test('urlToPath decodes file URLs and rejects others', () => {
  assert.equal(Model.urlToPath('file:///home/d/My%20File.png'), '/home/d/My File.png')
  assert.equal(Model.urlToPath('https://example.com/a'), '')
})

test('default profile follows the shared category, else mixed', () => {
  const imgs = Model.toFiles(['/a.png', '/b.jpg'], extMap)
  assert.equal(Model.selectDefaultProfile(imgs, formats).id, 'images')
  const mixed = Model.toFiles(['/a.png', '/b.pdf'], extMap)
  assert.equal(Model.selectDefaultProfile(mixed, formats).id, 'mixed')
  assert.equal(Model.selectDefaultProfile(Model.toFiles(['/x.unknown'], extMap), formats).id, 'mixed')
})

test('slicesFor keeps profile order and drops unknown presets', () => {
  const images = Model.DEFAULT_PROFILES.find(p => p.id === 'images')
  assert.deepEqual(plain(Model.slicesFor(images, presets)).map(s => s.id), ['to-png', 'to-jpg', 'to-pdf', 'half-size'])
})

test('user profiles follow Filee ProfileSelector', () => {
  const profiles = Model.parseUserProfiles(JSON.stringify([
    { id: 'img', extensions: ['png', 'jpg'], presetIds: ['to-pdf'] },
    { id: 'mix-img', isFallback: true, extensions: ['png', 'pdf'], presetIds: ['merge-pdf'] },
    { id: 'any', isFallback: true, extensions: [], presetIds: ['zip-all'] },
  ]))
  const pick = paths => Model.selectUserProfile(profiles, Model.toFiles(paths, extMap)).id
  assert.equal(pick(['/a.png', '/b.JPG']), 'img')
  assert.equal(pick(['/a.png', '/b.pdf']), 'mix-img')
  assert.equal(pick(['/a.png', '/b.zip']), 'any')
  assert.equal(Model.parseUserProfiles('not json'), null)
  assert.equal(Model.parseUserProfiles('[]'), null)
})

test('hitTest finds centre, slices clockwise from the top, and outside', () => {
  assert.equal(Model.hitTest(100, 100, 100, 100, 40, 90, 4).kind, 'center')
  assert.equal(Model.hitTest(100, 100, 100, 35, 40, 90, 4).index, 0)
  assert.equal(Model.hitTest(100, 100, 165, 100, 40, 90, 4).index, 1)
  assert.equal(Model.hitTest(100, 100, 100, 165, 40, 90, 4).index, 2)
  assert.equal(Model.hitTest(100, 100, 35, 100, 40, 90, 4).index, 3)
  assert.equal(Model.hitTest(100, 100, 100, 5, 40, 90, 4).kind, 'outside')
  assert.equal(Model.hitTest(100, 100, 100, 35, 40, 90, 0).kind, 'ring')
})

test('convertArgs uses the preset and skips unknown files', () => {
  const files = [{ path: '/a.png', format: 'png' }, { path: '/b', format: '' }]
  assert.deepEqual([...Model.convertArgs(files, 'to-webp')], ['convert', '/a.png', '--preset', 'to-webp', '--json'])
})

test('parseResult validates and summarize counts', () => {
  assert.equal(Model.parseResult('nope').ok, false)
  const r = Model.parseResult(JSON.stringify({ files: [
    { source: '/a', state: 'done', outputs: ['/a.webp'] },
    { source: '/b', state: 'failed', outputs: [1], error: 'bad' },
  ] }))
  const s = Model.summarize(r)
  assert.equal(s.ok, false)
  assert.equal(s.done, 1)
  assert.equal(s.error, 'bad')
  assert.deepEqual(plain(s.failedSources), ['/b'])
  assert.deepEqual(plain(s.outputs), ['/a.webp'])
})
