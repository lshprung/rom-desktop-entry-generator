#!/usr/bin/env sh

# BASEDIR is used to treat this script as a portable application
BASEDIR="$(dirname "$0")"
SCRIPTNAME="$(basename "$0" .sh)"
DESKTOP_ENTRY_OUTPUT_DIR="$BASEDIR/output"
DESKTOP_ENTRY_INSTALL_DIR="$HOME/.local/share/applications"
ICON_INSTALL_DIR="$HOME/.local/share/icons/hicolor"

# Build an individual .desktop entry given a name, rompath, and system
build_desktop_file() {
	NAME="$1"
	ROMPATH="$2"
	SYSTEM="$3"
	OUTPUT="$DESKTOP_ENTRY_OUTPUT_DIR/${SCRIPTNAME}_${SYSTEM}_${NAME}.desktop"

	echo "Building $NAME"

	# Check validity
	if [ -z "$NAME" ]; then
		echo "Skipping: missing NAME"
		return
	fi
	if [ -z "$ROMPATH" ]; then
		echo "Skipping: missing PATH"
		return
	fi
	if [ -z "$SYSTEM" ]; then
		echo "Skipping: missing SYSTEM"
		return
	fi
	if [ ! -r "$BASEDIR/config/systems/$SYSTEM" ]; then
		echo "Skipping: No configuration exists for SYSTEM"
		return
	fi
	# FIXME this warning can have false positives
	if [ ! -e "$ROMPATH" ]; then
		echo "Warning: PATH does not exist"
	fi

	# shellcheck source=/dev/null
	. "$BASEDIR/config/systems/$SYSTEM"

	mkdir -p "$DESKTOP_ENTRY_OUTPUT_DIR"
	echo "[Desktop Entry]" > "$OUTPUT"
	echo "Type=Application" >> "$OUTPUT"
	echo "Name=$NAME" >> "$OUTPUT"
	echo "Icon=${SCRIPTNAME}_${SYSTEM}_${NAME}" >> "$OUTPUT"
	echo "Exec=$launcher $flags $ROMPATH" >> "$OUTPUT"
	echo "Categories=Game" >> "$OUTPUT"

	echo "Installing $NAME"
	install_icon "$NAME" "$SYSTEM"
	install_desktop_file "$OUTPUT"
}

# empty the output directory
clean() {
	rm -rf "$BASEDIR/output"
}

install_desktop_file() {
	OUTPUT="$1"

	# TODO look into using xdg-desktop-menu for install and uninstall
	install "$OUTPUT" "$DESKTOP_ENTRY_INSTALL_DIR"
}

install_icon() {
	NAME="$1"
	SYSTEM="$2"
	ICON_SOURCE="$BASEDIR/icon/$SYSTEM/$NAME"
	ICON_EXTENSION=""

	# Try a number of file extensions for the icon source
	for extension in ".png"; do
		if [ -r "${ICON_SOURCE}${extension}" ]; then
			ICON_EXTENSION="$extension"
			break
		fi
	done

	if [ -z "$ICON_EXTENSION" ]; then
		echo "Icon does not exist or is not readable. Skipping icon installation"
		return
	fi

	# Append the extension to the source variable to avoid too much typing
	ICON_SOURCE="${ICON_SOURCE}${ICON_EXTENSION}"

	for size in "16" "24" "32" "48" "64" "96" "128" "256"; do
		convert "$ICON_SOURCE" -resize "${size}x${size}"\! "$ICON_INSTALL_DIR/${size}x${size}/apps/${SCRIPTNAME}_${SYSTEM}_$(basename "$ICON_SOURCE")"
	done
}

parse_config() {
	CONFIG_PATH="$1"

	while read -r line; do
		# Skip comments and empty lines
		if echo "$line" | grep -q ^#; then
			continue
		fi
		if [ -z "$line" ]; then
			continue
		fi

		eval "build_desktop_file $line"
	done < "$CONFIG_PATH"

	# Workaround to refresh icons
	touch "$ICON_INSTALL_DIR"
}

uninstall() {
	#NAME="$1"
	#ROMPATH="$2"
	#SYSTEM="$3"

	find "$BASEDIR/output/" -type f | while read -r file; do
		echo "Removing $(basename "$file")"

		# Remove icons
		ICON="$(grep "^Icon=" "$file" | cut -d "=" -f 2)"
		for size in "16" "24" "32" "48" "64" "96" "128" "256"; do
			rm -f "$ICON_INSTALL_DIR/${size}x${size}/apps/$ICON"*
		done

		# Remove the desktop entry
		rm -f "$DESKTOP_ENTRY_INSTALL_DIR/$(basename "$file")"
	done
}

# TODO allow for building without also installing
MODE="build"
case "$1" in
	clean)
		MODE="clean"
		eval $MODE
		;;
	uninstall)
		MODE="uninstall"
		eval $MODE
		;;
	*)
		parse_config "$BASEDIR/config/romlist"
		;;
esac
