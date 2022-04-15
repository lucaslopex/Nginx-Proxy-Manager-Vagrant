
		echo "WSL DETECTED: We recommend using Docker Desktop for Windows."
		echo "Please get Docker Desktop from https://www.docker.com/products/docker-desktop"
		echo
		cat >&2 <<-'EOF'

			You may press Ctrl+C now to abort this script.
		EOF
		( set -x; sleep 20 )
	fi

	case "$lsb_dist" in

		ubuntu)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --codename | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/lsb-release ]; then
				dist_version="$(. /etc/lsb-release && echo "$DISTRIB_CODENAME")"
			fi
		;;

		debian|raspbian)
			dist_version="$(sed 's/\/.*//' /etc/debian_version | sed 's/\..*//')"
			case "$dist_version" in
				11)
					dist_version="bullseye"
				;;
				10)
					dist_version="buster"
				;;
				9)
					dist_version="stretch"
				;;
				8)
					dist_version="jessie"
				;;
			esac
		;;

		centos|rhel|sles)
			if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
				dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
			fi
		;;

		*)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --release | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
				dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
			fi
		;;

	esac

	# Check if this is a forked Linux distro
	check_forked

	# Print deprecation warnings for distro versions that recently reached EOL,
	# but may still be commonly used (especially LTS versions).
	case "$lsb_dist.$dist_version" in
		debian.stretch|debian.jessie)
			deprecation_notice "$lsb_dist" "$dist_version"
			;;
		raspbian.stretch|raspbian.jessie)
			deprecation_notice "$lsb_dist" "$dist_version"
			;;
		ubuntu.xenial|ubuntu.trusty)
			deprecation_notice "$lsb_dist" "$dist_version"
			;;
		fedora.*)
			if [ "$dist_version" -lt 33 ]; then
				deprecation_notice "$lsb_dist" "$dist_version"
			fi
			;;
	esac

	# Run setup for each distro accordingly
	case "$lsb_dist" in
		ubuntu|debian|raspbian)
			pre_reqs="apt-transport-https ca-certificates curl"
			if ! command -v gpg > /dev/null; then
				pre_reqs="$pre_reqs gnupg"
			fi
			apt_repo="deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] $DOWNLOAD_URL/linux/$lsb_dist $dist_version $CHANNEL"
			(
				if ! is_dry_run; then
					set -x
				fi
				$sh_c 'apt-get update -qq >/dev/null'
				$sh_c "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $pre_reqs >/dev/null"
				$sh_c "curl -fsSL \"$DOWNLOAD_URL/linux/$lsb_dist/gpg\" | gpg --dearmor --yes -o /usr/share/keyrings/docker-archive-keyring.gpg"
				$sh_c "echo \"$apt_repo\" > /etc/apt/sources.list.d/docker.list"
				$sh_c 'apt-get update -qq >/dev/null'
			)
			pkg_version=""
			if [ -n "$VERSION" ]; then
				if is_dry_run; then
					echo "# WARNING: VERSION pinning is not supported in DRY_RUN"
				else
					# Will work for incomplete versions IE (17.12), but may not actually grab the "latest" if in the test channel
					pkg_pattern="$(echo "$VERSION" | sed "s/-ce-/~ce~.*/g" | sed "s/-/.*/g").*-0~$lsb_dist"
					search_command="apt-cache madison 'docker-ce' | grep '$pkg_pattern' | head -1 | awk '{\$1=\$1};1' | cut -d' ' -f 3"
					pkg_version="$($sh_c "$search_command")"
					echo "INFO: Searching repository for VERSION '$VERSION'"
					echo "INFO: $search_command"
					if [ -z "$pkg_version" ]; then
						echo
						echo "ERROR: '$VERSION' not found amongst apt-cache madison results"
						echo
						exit 1
					fi
					if version_gte "18.09"; then
							search_command="apt-cache madison 'docker-ce-cli' | grep '$pkg_pattern' | head -1 | awk '{\$1=\$1};1' | cut -d' ' -f 3"
							echo "INFO: $search_command"
							cli_pkg_version="=$($sh_c "$search_command")"
					fi
					pkg_version="=$pkg_version"
				fi
			fi
			(
				pkgs=""
				if version_gte "18.09"; then
						# older versions don't support a cli package
						pkgs="$pkgs docker-ce-cli${cli_pkg_version%=}"
				fi
				if version_gte "20.10" && [ "$(uname -m)" = "x86_64" ]; then
						# also install the latest version of the "docker scan" cli-plugin (only supported on x86 currently)
						pkgs="$pkgs docker-scan-plugin"
				fi
				pkgs="$pkgs docker-ce${pkg_version%=}"
				if ! is_dry_run; then
					set -x
				fi
				$sh_c "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends $pkgs >/dev/null"
				if version_gte "20.10"; then
					# Install docker-ce-rootless-extras without "--no-install-recommends", so as to install slirp4netns when available
					$sh_c "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-ce-rootless-extras${pkg_version%=} >/dev/null"
				fi
			)
			echo_docker_as_nonroot
			exit 0
			;;
		centos|fedora|rhel)
			if [ "$(uname -m)" != "s390x" ] && [ "$lsb_dist" = "rhel" ]; then
				echo "Packages for RHEL are currently only available for s390x."
				exit 1
			fi
			yum_repo="$DOWNLOAD_URL/linux/$lsb_dist/$REPO_FILE"
			if ! curl -Ifs "$yum_repo" > /dev/null; then
				echo "Error: Unable to curl repository file $yum_repo, is it valid?"
				exit 1
			fi
			if [ "$lsb_dist" = "fedora" ]; then
				pkg_manager="dnf"
				config_manager="dnf config-manager"
				enable_channel_flag="--set-enabled"
				disable_channel_flag="--set-disabled"
				pre_reqs="dnf-plugins-core"
				pkg_suffix="fc$dist_version"
			else
				pkg_manager="yum"
				config_manager="yum-config-manager"
				enable_channel_flag="--enable"
				disable_channel_flag="--disable"
				pre_reqs="yum-utils"
				pkg_suffix="el"
			fi
			(
				if ! is_dry_run; then
					set -x
				fi
				$sh_c "$pkg_manager install -y -q $pre_reqs"
				$sh_c "$config_manager --add-repo $yum_repo"

				if [ "$CHANNEL" != "stable" ]; then
					$sh_c "$config_manager $disable_channel_flag docker-ce-*"
					$sh_c "$config_manager $enable_channel_flag docker-ce-$CHANNEL"
				fi
				$sh_c "$pkg_manager makecache"
			)
			pkg_version=""
			if [ -n "$VERSION" ]; then
				if is_dry_run; then
					echo "# WARNING: VERSION pinning is not supported in DRY_RUN"
				else
					pkg_pattern="$(echo "$VERSION" | sed "s/-ce-/\\\\.ce.*/g" | sed "s/-/.*/g").*$pkg_suffix"
					search_command="$pkg_manager list --showduplicates 'docker-ce' | grep '$pkg_pattern' | tail -1 | awk '{print \$2}'"
					pkg_version="$($sh_c "$search_command")"
					echo "INFO: Searching repository for VERSION '$VERSION'"
					echo "INFO: $search_command"
					if [ -z "$pkg_version" ]; then
						echo
						echo "ERROR: '$VERSION' not found amongst $pkg_manager list results"
						echo
						exit 1
					fi
					if version_gte "18.09"; then
						# older versions don't support a cli package
						search_command="$pkg_manager list --showduplicates 'docker-ce-cli' | grep '$pkg_pattern' | tail -1 | awk '{print \$2}'"
						cli_pkg_version="$($sh_c "$search_command" | cut -d':' -f 2)"
					fi
					# Cut out the epoch and prefix with a '-'
					pkg_version="-$(echo "$pkg_version" | cut -d':' -f 2)"
				fi
			fi
			(
				if ! is_dry_run; then
					set -x
				fi
				# install the correct cli version first
				if [ -n "$cli_pkg_version" ]; then
					$sh_c "$pkg_manager install -y -q docker-ce-cli-$cli_pkg_version"
				fi
				$sh_c "$pkg_manager install -y -q docker-ce$pkg_version"
				if version_gte "20.10"; then
					$sh_c "$pkg_manager install -y -q docker-ce-rootless-extras$pkg_version"
				fi
			)
			echo_docker_as_nonroot
			exit 0
			;;
		sles)
			if [ "$(uname -m)" != "s390x" ]; then
				echo "Packages for SLES are currently only available for s390x"
				exit 1
			fi

			sles_version="${dist_version##*.}"
			sles_repo="$DOWNLOAD_URL/linux/$lsb_dist/$REPO_FILE"
			opensuse_repo="https://download.opensuse.org/repositories/security:SELinux/SLE_15_SP$sles_version/security:SELinux.repo"
			if ! curl -Ifs "$sles_repo" > /dev/null; then
				echo "Error: Unable to curl repository file $sles_repo, is it valid?"
				exit 1
			fi
			pre_reqs="ca-certificates curl libseccomp2 awk"
			(
				if ! is_dry_run; then
					set -x
				fi
				$sh_c "zypper install -y $pre_reqs"
				$sh_c "zypper addrepo $sles_repo"
				if ! is_dry_run; then
						cat >&2 <<-'EOF'
						WARNING!!
						openSUSE repository (https://download.opensuse.org/repositories/security:SELinux) will be enabled now.
						Do you wish to continue?
						You may press Ctrl+C now to abort this script.
						EOF
						( set -x; sleep 30 )
				fi
				$sh_c "zypper addrepo $opensuse_repo"
				$sh_c "zypper --gpg-auto-import-keys refresh"
				$sh_c "zypper lr -d"
			)
			pkg_version=""
			if [ -n "$VERSION" ]; then
				if is_dry_run; then
					echo "# WARNING: VERSION pinning is not supported in DRY_RUN"
				else
					pkg_pattern="$(echo "$VERSION" | sed "s/-ce-/\\\\.ce.*/g" | sed "s/-/.*/g")"
					search_command="zypper search -s --match-exact 'docker-ce' | grep '$pkg_pattern' | tail -1 | awk '{print \$6}'"
					pkg_version="$($sh_c "$search_command")"
					echo "INFO: Searching repository for VERSION '$VERSION'"
					echo "INFO: $search_command"
					if [ -z "$pkg_version" ]; then
						echo
						echo "ERROR: '$VERSION' not found amongst zypper list results"
						echo
						exit 1
					fi
					search_command="zypper search -s --match-exact 'docker-ce-cli' | grep '$pkg_pattern' | tail -1 | awk '{print \$6}'"
					# It's okay for cli_pkg_version to be blank, since older versions don't support a cli package
					cli_pkg_version="$($sh_c "$search_command")"
					pkg_version="-$pkg_version"

					search_command="zypper search -s --match-exact 'docker-ce-rootless-extras' | grep '$pkg_pattern' | tail -1 | awk '{print \$6}'"
					rootless_pkg_version="$($sh_c "$search_command")"
					rootless_pkg_version="-$rootless_pkg_version"
				fi
			fi
			(
				if ! is_dry_run; then
					set -x
				fi
				# install the correct cli version first
				if [ -n "$cli_pkg_version" ]; then
					$sh_c "zypper install -y  docker-ce-cli-$cli_pkg_version"
				fi
				$sh_c "zypper install -y docker-ce$pkg_version"
				if version_gte "20.10"; then
					$sh_c "zypper install -y docker-ce-rootless-extras$rootless_pkg_version"
				fi
			)
			echo_docker_as_nonroot
			exit 0
			;;
		*)
			if [ -z "$lsb_dist" ]; then
				if is_darwin; then
					echo
					echo "ERROR: Unsupported operating system 'macOS'"
					echo "Please get Docker Desktop from https://www.docker.com/products/docker-desktop"
					echo
					exit 1
				fi
			fi
			echo
			echo "ERROR: Unsupported distribution '$lsb_dist'"
			echo
			exit 1
			;;
	esac
	exit 1
}

# wrapped up in a function so that we have some protection against only getting
# half the file during "curl | sh"
do_install

