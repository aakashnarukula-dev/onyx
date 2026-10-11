# Pick the SDK to build against. With only the Command Line Tools, the newest SDK's frameworks
# can need Swift macro plugins the CLT don't ship, so prefer the 26.5 SDK when it is there.
# Otherwise (Xcode, or other CLT versions) leave the toolchain's default alone.
PINNED=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
if [[ -z "${SDKROOT:-}" && -d "$PINNED" && "$(xcode-select -p 2>/dev/null)" == /Library/Developer/CommandLineTools ]]; then
  export SDKROOT=$PINNED
fi
unset PINNED
