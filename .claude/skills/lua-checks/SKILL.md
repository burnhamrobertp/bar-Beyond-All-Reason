---
name: lua-checks
description: Run this repo's Lua CI checks locally before pushing - stylua formatting and the busted specs. Use this whenever you have edited a .lua file under luaui/, luarules/, common/ or spec/ and are about to commit, push, or open a PR, and whenever a pull request comes back red on the stylua or busted checks. Also use it when asked to run the tests, run the specs, check formatting, or verify a Lua change, since lux and busted are usually not installed locally and there is a LuaJIT-based stand-in here instead.
---

# Running the Lua checks locally

CI runs two checks that a Lua change can fail, and both are cheap to run here first.

Compiling a file with `loadfile` is not one of them. It proves the file parses and nothing
else - a spec can parse perfectly and still assert the wrong thing.

## Formatting

stylua is on PATH. CI pins 2.5.2 and fails on any hunk the pull request wrote that is not
formatted, so run it over the files you touched and commit the result:

```bash
stylua <files you changed>
stylua --version   # confirm 2.5.2 if CI disagrees with what you see here
```

## Specs

CI runs `lx --lua-version 5.1 test`, which needs lux and busted. When those are not
installed, run the specs through the stand-in in this skill instead:

```bash
"$LOCALAPPDATA/Programs/LuaJIT/bin/luajit.exe" .claude/skills/lua-checks/scripts/run_specs.lua spec/path/to/a_spec.lua
```

Several files at once is fine, and this runs the lot:

```bash
"$LOCALAPPDATA/Programs/LuaJIT/bin/luajit.exe" .claude/skills/lua-checks/scripts/run_specs.lua $(find spec -name "*_spec.lua" | tr '\n' ' ')
```

It loads the repo's own `spec/spec_helper.lua`, so the `Spring`, `VFS` and `Game` stubs are
the ones the specs are written against rather than a second set that can drift from them.

## What the stand-in is not

It is a few hundred lines of `describe`/`it`/`assert` written against what this repo's specs
happen to use, not busted. Treat a green run as "worth pushing", never as "CI will pass".

An assertion it does not implement raises rather than returning nil, because a missing
assertion that quietly returns nothing reads as a pass and would make the whole run
worthless. If you hit one, add it to `scripts/run_specs.lua` alongside the others.

`spec/common/json_spec.lua` does not parse under LuaJIT at all - it contains a `\u` escape
that CI's Lua accepts and this one rejects - so it is skipped with a load failure. Everything
else in `spec/` runs.

If CI fails on something that passed here, the difference is the stand-in, and the fix
belongs in `scripts/run_specs.lua` so the next person does not lose the same afternoon.
