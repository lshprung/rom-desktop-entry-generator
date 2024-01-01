#!/usr/bin/env sh

# BASEDIR is used to treat this script as a portable application
BASEDIR="$(dirname "$0")"
SCRIPTNAME="$(basename "$0" .sh)"
DESKTOP_ENTRY_OUTPUT_DIR="$BASEDIR/output"
DESKTOP_ENTRY_INSTALL_DIR="$HOME/.local/share/applications"
ICON_SOURCE_DIR="$BASEDIR/icon"
ICON_INSTALL_DIR="$HOME/.local/share/icons/hicolor"

# Build an individual .desktop entry given a name, rompath, and system
# Usage: build_desktop_file NAME ROMPATH SYSTEM
build_desktop_file() {
	NAME="$1"
	ROMPATH="$2"
	SYSTEM="$3"
	OUTPUT="$DESKTOP_ENTRY_OUTPUT_DIR/$SYSTEM/${SCRIPTNAME}_${SYSTEM}_${NAME}.desktop"

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

	unset launcher
	unset flags
	# shellcheck source=/dev/null
	. "$BASEDIR/config/systems/$SYSTEM"

	mkdir -p "$DESKTOP_ENTRY_OUTPUT_DIR/$SYSTEM"
	echo "[Desktop Entry]" > "$OUTPUT"
	echo "Type=Application" >> "$OUTPUT"
	echo "Name=$NAME" >> "$OUTPUT"
	echo "Icon=${SCRIPTNAME}_${SYSTEM}_${NAME}" >> "$OUTPUT"
	echo "Exec=$launcher $flags $ROMPATH" >> "$OUTPUT"
	echo "Categories=Game" >> "$OUTPUT"

	#echo "Installing $NAME"
	#install_icon "$NAME" "$SYSTEM"
	#install_desktop_file "$OUTPUT"
}

# Wrapper for a call to build
# Usage: build_wrapper TARGET_SYSTEMS...
build_wrapper() {
	# find all romlist files in config if --system is not specified
	if [ -z "$1" ]; then
		find "$BASEDIR/config/" -name 'romlist_*' | while read -r file; do
			parse_config "$file"
		done
	else
		while [ -n "$1" ]; do
			if [ -r "$BASEDIR/config/romlist_$1" ]; then
				parse_config "$BASEDIR/config/romlist_$1"
			fi
			shift
		done
	fi
}

# empty the output directory
# Usage: clean_wrapper TARGET_SYSTEMS...
clean_wrapper() {
	while [ -n "$1" ]; do
		echo "Removing $DESKTOP_ENTRY_OUTPUT_DIR/$1"
		rm -rf "${DESKTOP_ENTRY_OUTPUT_DIR:?}/$1"
		shift
	done

	rmdir --ignore-fail-on-non-empty "$DESKTOP_ENTRY_OUTPUT_DIR"
}

# help message
# Usage: help
help() {
	echo "Usage: $0 [OPTION]... [TARGET]..."
	echo "Generate desktop entries for video game roms"
	echo
	echo "Targets:"
	echo "  build                   build desktop entries into $DESKTOP_ENTRY_OUTPUT_DIR"
	echo "  clean                   remove $DESKTOP_ENTRY_OUTPUT_DIR and its contents (also calls uninstall target)"
	echo "  install                 install desktop entries into $DESKTOP_ENTRY_INSTALL_DIR"
	echo "  uninstall               uninstall desktop entries from $DESKTOP_ENTRY_INSTALL_DIR"
	echo
	echo "Options"
	echo "  -h, --help              print this help message and exit"
	echo "      --icon-dir [DIR]    Specify an icon source directory (default is $ICON_SOURCE_DIR)"
	echo "  -s, --system [SYSTEM]   Specify a system, or comma-separated list of systems. Default is all systems"
}

# Usage: install_icon NAME SYSTEM
install_icon() {
	NAME="$1"
	SYSTEM="$2"
	ICON_SOURCE="$ICON_SOURCE_DIR/$SYSTEM/$NAME"
	ICON_EXTENSION=""

	# Try a number of file extensions for the icon source
	for extension in ".png" ".svg" ".svgz" ".xpm"; do
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

# Wrapper for a call to install
# Usage: install_wrapper TARGET_SYSTEMS...
install_wrapper() {
	while [ -n "$1" ]; do
		find "$DESKTOP_ENTRY_OUTPUT_DIR/$1" -type f | while read -r file; do
			echo "Installing $file"

			# Install desktop entry
			# TODO look into using xdg-desktop-menu for install and uninstall
			install "$file" "$DESKTOP_ENTRY_INSTALL_DIR"

			# Install icon
			NAME="$(grep "^Name=" "$file" | cut -d "=" -f 2)"
			SYSTEM="$(basename "$(dirname "$file")")"
			install_icon "$NAME" "$SYSTEM"
		done

		shift
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
}

# Usage: uninstall_wrapper TARGET_SYSTEMS...
uninstall_wrapper() {
	while [ -n "$1" ]; do
		find "$DESKTOP_ENTRY_OUTPUT_DIR/$1" -type f | while read -r file; do
			echo "Uninstalling $(basename "$file")"

			# Remove icons
			ICON="$(grep "^Icon=" "$file" | cut -d "=" -f 2)"
			for size in "16" "24" "32" "48" "64" "96" "128" "256"; do
				rm -f "$ICON_INSTALL_DIR/${size}x${size}/apps/$ICON"*
			done

			# Remove the desktop entry
			rm -f "$DESKTOP_ENTRY_INSTALL_DIR/$(basename "$file")"
		done
		
		shift
	done
}

# Read arguments
GETOPT=$(getopt -o 'hs:' --long 'help,icon-dir:,system:' -n "$(basename "$0")" -- "$@")

# Terminate if getopt goes wrong
if [ $? -ne 0 ]; then
	echo "Terminating..." >&2
	exit 1
fi

eval set -- "$GETOPT"
unset GETOPT

while true; do
	echo "$1"
	case "$1" in
		'-h'|'--help')
			help
			exit
			;;
		'--icon-dir')
			shift
			ICON_SOURCE_DIR="$1"
			shift
			continue
			;;
		'-s'|'--system')
			shift
			TARGET_SYSTEMS="$(echo "$1" | tr ',' ' ')"
			shift
			continue
			;;
		'--')
			shift
			break
			;;
		*)
			echo "Internal error!" >&2
			exit 1
			;;
	esac
done

# By default, build, but do not install
if [ -z "$1" ]; then
	build_wrapper
fi

while [ -n "$1" ]; do
	case "$1" in
		build)
			if [ -z "$TARGET_SYSTEMS" ]; then
				TARGET_SYSTEMS="$(find "$BASEDIR/config" -type f -name 'romlist_*' -exec sh -c 'basename {} | cut -d '_' -f 2' \;)"
			fi
			build_wrapper $TARGET_SYSTEMS
			shift
			continue
			;;
		clean)
			if [ -z "$TARGET_SYSTEMS" ]; then
				TARGET_SYSTEMS="$(ls -1 "$DESKTOP_ENTRY_OUTPUT_DIR")"
			fi
			uninstall_wrapper $TARGET_SYSTEMS
			clean_wrapper $TARGET_SYSTEMS
			shift
			continue
			;;
		install)
			if [ -z "$TARGET_SYSTEMS" ]; then
				TARGET_SYSTEMS="$(ls -1 "$DESKTOP_ENTRY_OUTPUT_DIR")"
			fi
			install_wrapper $TARGET_SYSTEMS
			# Workaround to refresh icons
			touch "$ICON_INSTALL_DIR"
			shift
			continue
			;;
		uninstall)
			if [ -z "$TARGET_SYSTEMS" ]; then
				TARGET_SYSTEMS="$(ls -1 "$DESKTOP_ENTRY_OUTPUT_DIR")"
			fi
			uninstall_wrapper $TARGET_SYSTEMS
			shift
			continue
			;;
	esac
done
