#!/usr/bin/env sh

# Technical variables
STDOUT_LOG=/dev/stdout
STDERR_LOG=/dev/stderr

# BASEDIR is used to treat this script as a portable application
BASEDIR="$(dirname "$0")"
SCRIPTNAME="$(basename "$0" .sh)"
CONFIG_DIR=""
DESKTOP_ENTRY_OUTPUT_DIR="$BASEDIR/output"
DESKTOP_ENTRY_INSTALL_DIR="$HOME/.local/share/applications/$SCRIPTNAME"
ICON_SOURCE_DIR="$BASEDIR/icon"
ICON_INSTALL_DIR="$HOME/.local/share/icons/hicolor"

# Build an individual .desktop entry given a name, rompath, and system
# Usage: build_desktop_file NAME ROMPATH SYSTEM
build_desktop_file() {
	NAME="$1"
	ROMPATH="$2"
	SYSTEM="$3"
	OUTPUT="$DESKTOP_ENTRY_OUTPUT_DIR/$SYSTEM/$NAME.desktop"

	echo "Building $NAME" >> "$STDOUT_LOG"

	# Check validity
	if [ -z "$NAME" ]; then
		echo "Skipping: missing NAME" >> "$STDOUT_LOG"
		return
	fi
	if [ -z "$ROMPATH" ]; then
		echo "Skipping: missing PATH" >> "$STDOUT_LOG"
		return
	fi
	if [ -z "$SYSTEM" ]; then
		echo "Skipping: missing SYSTEM" >> "$STDOUT_LOG"
		return
	fi
	if [ ! -r "$(dirname "$CONFIG_DIR")/systems/$SYSTEM" ]; then
		echo "Skipping: No configuration exists for $SYSTEM" >> "$STDOUT_LOG"
		return
	fi
	if ! eval test -e "\"$ROMPATH\""; then
		echo "Warning: PATH $ROMPATH does not exist" >> "$STDOUT_LOG"
	fi

	unset launcher
	unset flags
	# shellcheck source=/dev/null
	. "$(dirname "$CONFIG_DIR")/systems/$SYSTEM"

	mkdir -p "$DESKTOP_ENTRY_OUTPUT_DIR/$SYSTEM"
	echo "[Desktop Entry]" > "$OUTPUT"
	echo "Type=Application" >> "$OUTPUT"
	echo "Name=$NAME" >> "$OUTPUT"
	echo "Icon=${SCRIPTNAME}_${SYSTEM}_${NAME}" >> "$OUTPUT"
	echo "Exec=$launcher $flags \"$ROMPATH\"" >> "$OUTPUT"
	echo "Categories=Game" >> "$OUTPUT"
}

# Wrapper for a call to build
# Usage: build_wrapper TARGET_SYSTEMS...
build_wrapper() {
	# find all romlist files in config if --system is not specified
	if [ -z "$1" ]; then
		find "$CONFIG_DIR" -name 'romlist_*' | while read -r file; do
			parse_config "$file"
		done
	else
		while [ -n "$1" ]; do
			if [ -r "$CONFIG_DIR/romlist_$1" ]; then
				parse_config "$CONFIG_DIR/romlist_$1"
			fi
			shift
		done
	fi
}

# empty the output directory
# Usage: clean_wrapper TARGET_SYSTEMS...
clean_wrapper() {
	while [ -n "$1" ]; do
		echo "Removing $DESKTOP_ENTRY_OUTPUT_DIR/$1" >> "$STDOUT_LOG"
		rm -rf "${DESKTOP_ENTRY_OUTPUT_DIR:?}/$1"
		shift
	done

	rmdir --ignore-fail-on-non-empty "$DESKTOP_ENTRY_OUTPUT_DIR"
}

# checks for config location
# Usage: get_config_dir
get_config_dir() {
	for path in "$HOME/.config/$SCRIPTNAME" "$HOME/.$SCRIPTNAME" "/etc/$SCRIPTNAME"; do
		if [ -d "$path" ]; then
			CONFIG_DIR="$path"
			return
		fi
	done
}

# help message
# Usage: help
help() {
	echo "Usage: $0 [OPTION]... TARGET..." >> "$STDERR_LOG"
	echo "Generate desktop entries for video game roms" >> "$STDERR_LOG"
	echo >> "$STDERR_LOG"
	echo "Targets:" >> "$STDERR_LOG"
	echo "  build                   build desktop entries into $DESKTOP_ENTRY_OUTPUT_DIR" >> "$STDERR_LOG"
	echo "  clean                   remove $DESKTOP_ENTRY_OUTPUT_DIR and its contents (also calls uninstall target)" >> "$STDERR_LOG"
	echo "  install                 install desktop entries into $DESKTOP_ENTRY_INSTALL_DIR" >> "$STDERR_LOG"
	echo "  uninstall               uninstall desktop entries from $DESKTOP_ENTRY_INSTALL_DIR" >> "$STDERR_LOG"
	echo >> "$STDERR_LOG"
	echo "Options" >> "$STDERR_LOG"
	echo "  -c, --config            specify a configuration directory (default is $HOME/.config/$SCRIPTNAME)" >> "$STDERR_LOG"
	echo "  -h, --help              print this help message and exit" >> "$STDERR_LOG"
	echo "  -i, --icon-dir [DIR]    specify an icon source directory (default is $ICON_SOURCE_DIR)" >> "$STDERR_LOG"
	echo "  -q, --quiet             do not print to stdout" >> "$STDERR_LOG"
	echo "  -s, --system [SYSTEM]   specify a system, or comma-separated list of systems. Default is all systems" >> "$STDERR_LOG"
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
		echo "Icon does not exist or is not readable. Skipping icon installation" >> "$STDOUT_LOG"
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
			echo "Installing $file" >> "$STDOUT_LOG"

			NAME="$(grep "^Name=" "$file" | cut -d "=" -f 2)"
			SYSTEM="$(basename "$(dirname "$file")")"

			# Install desktop entry
			# TODO look into using xdg-desktop-menu for install and uninstall
			mkdir -p "$DESKTOP_ENTRY_INSTALL_DIR/$SYSTEM"
			install "$file" "$DESKTOP_ENTRY_INSTALL_DIR/$SYSTEM"

			# Install icon
			install_icon "$NAME" "$SYSTEM"
		done

		shift
	done
}

parse_config() {
	CONFIG_DIR="$1"

	while read -r line; do
		# Skip comments and empty lines
		if echo "$line" | grep -q ^#; then
			continue
		fi
		if [ -z "$line" ]; then
			continue
		fi

		eval "build_desktop_file $line"
	done < "$CONFIG_DIR"
}

# Usage: uninstall_wrapper TARGET_SYSTEMS...
uninstall_wrapper() {
	while [ -n "$1" ]; do
		find "$DESKTOP_ENTRY_OUTPUT_DIR/$1" -type f | while read -r file; do
			echo "Uninstalling $(basename "$file")" >> "$STDOUT_LOG"

			# Remove icons
			ICON="$(grep "^Icon=" "$file" | cut -d "=" -f 2)"
			for size in "16" "24" "32" "48" "64" "96" "128" "256"; do
				rm -f "$ICON_INSTALL_DIR/${size}x${size}/apps/$ICON"*
			done

			# Remove the desktop entry
			rm -f "$DESKTOP_ENTRY_INSTALL_DIR/$(basename "$(dirname "$file")")/$(basename "$file")"
			rmdir --ignore-fail-on-non-empty "$DESKTOP_ENTRY_INSTALL_DIR/$(basename "$(dirname "$file")")"
			rmdir --ignore-fail-on-non-empty "$DESKTOP_ENTRY_INSTALL_DIR"
		done
		
		shift
	done
}

# Read arguments
GETOPT=$(getopt -o 'c:hi:qs:' --long 'config:,help,icon-dir:,quiet,system:' -n "$(basename "$0")" -- "$@")

# Terminate if getopt goes wrong
if [ $? -ne 0 ]; then
	echo "Terminating..." >> "$STDERR_LOG"
	exit 1
fi

eval set -- "$GETOPT"
unset GETOPT

while true; do
	case "$1" in
		'-c'|'--config')
			shift
			CONFIG_DIR="$1"
			shift
			continue
			;;
		'-h'|'--help')
			help
			exit
			;;
		'-i'|'--icon-dir')
			shift
			ICON_SOURCE_DIR="$1"
			shift
			continue
			;;
		'-q'|'--quiet')
			STDOUT_LOG=/dev/null
			shift
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
			echo "Internal error!" >> "$STDERR_LOG"
			exit 1
			;;
	esac
done

# Set CONFIG_DIR if not already set by flags
if [ -z "$CONFIG_DIR" ]; then
	get_config_dir
fi
# Check that CONFIG_DIR is real
if [ ! -d "$CONFIG_DIR" ]; then
	echo "Error: could not load configuration at '$CONFIG_DIR'; directory does not exist" >> "$STDERR_LOG"
	exit 1
fi

# By default, build, but do not install
if [ -z "$1" ]; then
	build_wrapper
fi

while [ -n "$1" ]; do
	case "$1" in
		build)
			shift
			if [ -z "$TARGET_SYSTEMS" ]; then
				TARGET_SYSTEMS="$(find "$CONFIG_DIR" -type f -name 'romlist_*' -exec sh -c 'basename {} | cut -d '_' -f 2' \;)"
			fi
			build_wrapper $TARGET_SYSTEMS
			continue
			;;
		clean)
			shift
			if [ ! -e "$DESKTOP_ENTRY_OUTPUT_DIR" ]; then
				continue
			fi
			if [ -z "$TARGET_SYSTEMS" ]; then
				TARGET_SYSTEMS="$(ls -1 "$DESKTOP_ENTRY_OUTPUT_DIR")"
			fi
			uninstall_wrapper $TARGET_SYSTEMS
			clean_wrapper $TARGET_SYSTEMS
			continue
			;;
		install)
			shift
			if [ -z "$TARGET_SYSTEMS" ]; then
				TARGET_SYSTEMS="$(ls -1 "$DESKTOP_ENTRY_OUTPUT_DIR")"
			fi
			install_wrapper $TARGET_SYSTEMS
			# Workaround to refresh icons
			touch "$ICON_INSTALL_DIR"
			# Workaround to refresh desktop database
			touch "$DESKTOP_ENTRY_INSTALL_DIR"
			continue
			;;
		uninstall)
			shift
			if [ -z "$TARGET_SYSTEMS" ]; then
				TARGET_SYSTEMS="$(ls -1 "$DESKTOP_ENTRY_OUTPUT_DIR")"
			fi
			uninstall_wrapper $TARGET_SYSTEMS
			# Workaround to refresh desktop database
			touch "$(dirname "$DESKTOP_ENTRY_INSTALL_DIR")"
			continue
			;;
	esac
done
