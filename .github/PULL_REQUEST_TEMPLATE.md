## What & why


## Checklist
- [ ] No secrets committed (localKey, apiKey, `.p8`, `options.json`, `Local.xcconfig`)
- [ ] emberd changes: `python -m py_compile` clean — iOS changes: `xcodegen generate && xcodebuild … build` succeeds
- [ ] Docs updated if behavior or config changed
- [ ] If it touches heater control: considered the safety / auth implications
