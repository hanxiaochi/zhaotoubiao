import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

// Isolated controller unit tests; real DOM/focus/Turbo behavior is separately
// exercised in the PC browser. No third-party npm dependencies are needed.
const source = readFileSync(new URL("../../app/javascript/controllers/confirm_controller.js", import.meta.url), "utf8")
  .replace(/^import .*$/gm, "")
  .replace("export default class", "class ConfirmController")

function setup() {
  const events = new Map()
  const previous = () => true
  const Turbo = { config: { forms: { confirm: previous } } }
  const opener = { isConnected: true, focusCount: 0, focus() { this.focusCount++ } }
  const document = { activeElement: opener,
    addEventListener(name, handler) { events.set(name, handler) },
    removeEventListener(name, handler) { if (events.get(name) === handler) events.delete(name) } }
  const Controller = vm.runInNewContext(`${source}; ConfirmController`, { Controller: class {}, Turbo, document })
  const controller = new Controller()
  controller.element = { open: false, closes: 0, showModal() { this.open = true }, close() { this.open = false; this.closes++ } }
  controller.messageTarget = { textContent: "" }
  controller.cancelTarget = { focusCount: 0, focus() { this.focusCount++ } }
  controller.connect()
  return { controller, Turbo, previous, opener, events }
}

test("prompt is literal text, defaults to cancel focus, and does not resolve before acceptance", async () => {
  const { controller, Turbo, opener } = setup()
  let settled = false
  const result = Turbo.config.forms.confirm('<script>not executable</script>').then(value => { settled = true; return value })
  await Promise.resolve()
  assert.equal(settled, false)
  assert.equal(controller.messageTarget.textContent, '<script>not executable</script>')
  assert.equal(controller.element.open, true)
  assert.equal(controller.cancelTarget.focusCount, 1)
  controller.accept()
  assert.equal(await result, true)
  assert.equal(controller.element.open, false)
  assert.equal(opener.focusCount, 1)
  controller.accept()
  assert.equal(controller.element.closes, 1)
})

test("cancel and Escape do not approve and allow another prompt", async () => {
  const { controller } = setup()
  for (let attempt = 0; attempt < 2; attempt++) {
    let prevented = false
    const result = controller.request("irreversible action")
    controller.cancel({ preventDefault() { prevented = true } })
    assert.equal(await result, false)
    assert.equal(prevented, true)
  }
})

test("concurrent confirmation is rejected, without replacing first prompt", async () => {
  const { controller } = setup()
  const first = controller.request("first")
  assert.equal(await controller.request("second"), false)
  assert.equal(controller.messageTarget.textContent, "first")
  controller.accept()
  assert.equal(await first, true)
})

test("cache navigation cancels pending prompt", async () => {
  const { controller, events } = setup()
  const pending = controller.request("navigate away")
  events.get("turbo:before-cache")()
  assert.equal(await pending, false)
  assert.equal(controller.element.open, false)
})

test("disconnect cancels and restores handler without overwriting a new controller", async () => {
  const { controller, Turbo, previous, events } = setup()
  const pending = controller.request("disconnect")
  controller.disconnect()
  assert.equal(await pending, false)
  assert.equal(Turbo.config.forms.confirm, previous)
  assert.equal(events.size, 0)
  controller.connect()
  const newerHandler = () => false
  Turbo.config.forms.confirm = newerHandler
  controller.disconnect()
  assert.equal(Turbo.config.forms.confirm, newerHandler)
})

test("unexpected dialog close cancels, but stale close does not cancel a newly opened prompt", async () => {
  const { controller } = setup()
  const first = controller.request("first")
  controller.element.open = false
  controller.closed()
  assert.equal(await first, false)
  let settled = false
  const second = controller.request("second").then(value => { settled = true; return value })
  controller.closed()
  await Promise.resolve()
  assert.equal(settled, false)
  controller.accept()
  assert.equal(await second, true)
})
