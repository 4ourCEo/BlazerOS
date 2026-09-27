#!/bin/zsh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Xcode is required. Command Line Tools cannot compile the iPhone 16 target."
  exit 1
fi
destination='platform=iOS Simulator,name=iPhone 16'
project="$root/iPhone/BlazerOS.xcodeproj"
sign=(CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES)
xcodebuild -project "$project" -scheme BlazerOS -destination "$destination" -configuration Debug "${sign[@]}" build
xcodebuild -project "$project" -scheme BlazerOS -destination "$destination" -configuration Release "${sign[@]}" build
xcodebuild -project "$project" -scheme BlazerOS -destination "$destination" -configuration Debug "${sign[@]}" test
