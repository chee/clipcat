#!/bin/sh
# builds and signs Clipcat.app (make bundle), zips it, and puts it on a github
# release, so there's a link to hand out:
#   https://github.com/<you>/clipcat/releases/latest/download/Clipcat.zip
#
# usage: support/release.sh [tag]     tag defaults to v<CFBundleShortVersionString>
# needs: gh, logged in (gh auth login), and the xcode command line tools.
# running it again with the same tag replaces the zip on that release.
#
# to notarize (needs a Developer ID Application identity), first store credentials:
#   xcrun notarytool store-credentials clipcat --apple-id you@example.com --team-id ABCDE12345
# then run with CLIPCAT_NOTARY_PROFILE=clipcat
set -eu
cd "$(dirname "$0")/.."

make bundle

app=build/Clipcat.app
zip=build/Clipcat.zip
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
tag=${1:-v$version}
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)

pack() {
	rm -f "$zip"
	# ditto keeps the signature intact; plain zip can break it
	ditto -c -k --keepParent "$app" "$zip"
}

pack
if [ -n "${CLIPCAT_NOTARY_PROFILE:-}" ]; then
	xcrun notarytool submit "$zip" --keychain-profile "$CLIPCAT_NOTARY_PROFILE" --wait
	xcrun stapler staple "$app"
	pack
fi

if gh release view "$tag" >/dev/null 2>&1; then
	gh release upload "$tag" "$zip" --clobber
else
	git push origin HEAD
	gh release create "$tag" "$zip" \
		--target "$(git rev-parse HEAD)" \
		--title "clipcat $version" \
		--notes "unzip, move Clipcat.app to Applications, open it."
fi

echo
echo "https://github.com/$repo/releases/download/$tag/Clipcat.zip"
echo "https://github.com/$repo/releases/latest/download/Clipcat.zip"
