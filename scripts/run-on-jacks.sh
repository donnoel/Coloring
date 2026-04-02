#!/bin/zsh
open -a Xcode /Users/donnoel/Development/Coloring/Coloring.xcodeproj
osascript <<'APPLESCRIPT'
tell application "Xcode" to activate
delay 1
tell application "System Events"
    keystroke "r" using command down
end tell
APPLESCRIPT
