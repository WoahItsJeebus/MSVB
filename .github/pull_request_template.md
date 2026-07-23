## Summary

Describe the problem and the user-visible result.

## Validation

- [ ] `pnpm run build`
- [ ] `pnpm test`
- [ ] Relevant manual launch paths tested in Steam
- [ ] Documentation and changelog updated when needed

## Safety review

- [ ] Unsupported or ambiguous launch paths still fail open.
- [ ] New parsing, process, filesystem, and RPC operations are validated and bounded.
- [ ] Logs and errors do not expose full paths, launch arguments, or profile data.
- [ ] The change does not claim Steam continuation removes deployed mods.
