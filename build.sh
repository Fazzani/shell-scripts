#!/usr/bin/env bash

# ##################################################
# Aws build application script
#
version="1.0.0"               # Sets version variable
#
scriptTemplateVersion="1.5.0" # Version of scriptTemplate.sh that this script is based on
#                               v1.1.0 -  Added 'debug' option
#                               v1.1.1 -  Moved all shared variables to Utils
#                                      -  Added $PASS variable when -p is passed
#                               v1.2.0 -  Added 'checkDependencies' function to ensure needed
#                                         Bash packages are installed prior to execution
#                               v1.3.0 -  Can now pass CLI without an option to $args
#                               v1.4.0 -  checkDependencies now checks gems and mac apps via
#                                         Homebrew cask
#                               v1.5.0 - Now has preferred IFS setting
#                                      - Preset flags now respect true/false
#                                      - Moved 'safeExit' function into template where it should
#                                        have been all along.
#
# HISTORY:
#
# * DATE - v1.0.0  - First Creation
#
# ##################################################

# Provide a variable with the location of this script.
scriptPath="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source Scripting Utilities
# -----------------------------------
# These shared utilities provide many functions which are needed to provide
# the functionality in this boilerplate. This script will fail if they can
# not be found.
# -----------------------------------

utilsLocation="${scriptPath}/lib/utils.sh" # Update this path to find the utilities.

if [ -f "${utilsLocation}" ]; then
  source "${utilsLocation}"
else
  echo "Please find the file util.sh and add a reference to it in this script. Exiting."
  exit 1
fi

# trapCleanup Function
# -----------------------------------
# Any actions that should be taken if the script is prematurely
# exited.  Always call this function at the top of your script.
# -----------------------------------
function trapCleanup() {
  echo ""
  # Delete temp files, if any
  if is_dir "${tmpDir}"; then
    rm -r "${tmpDir}"
  fi
  die "Exit trapped. In function: '${FUNCNAME[*]}'"
}

# safeExit
# -----------------------------------
# Non destructive exit for when script exits naturally.
# Usage: Add this function at the end of every script.
# -----------------------------------
function safeExit() {
  # Delete temp files, if any
  if is_dir "${tmpDir}"; then
    rm -r "${tmpDir}"
  fi
  trap - INT TERM EXIT
  exit
}

# Set Flags
# -----------------------------------
# Flags which can be overridden by user input.
# Default values are below
# -----------------------------------
quiet=false
printLog=false
verbose=false
force=false
strict=false
debug=false
args=()

# Set Temp Directory
# -----------------------------------
# Create temp directory with three random numbers and the process ID
# in the name.  This directory is removed automatically at exit.
# -----------------------------------
tmpDir="/tmp/${scriptName}.$RANDOM.$RANDOM.$RANDOM.$$"
(umask 077 && mkdir "${tmpDir}") || {
  die "Could not create temporary directory! Exiting."
}

# Logging
# -----------------------------------
# Log is only used when the '-l' flag is set.
#
# To never save a logfile change variable to '/dev/null'
# Save to Desktop use: $HOME/Desktop/${scriptBasename}.log
# Save to standard user log location use: $HOME/Library/Logs/${scriptBasename}.log
# -----------------------------------
logFile="$HOME/Library/Logs/${scriptBasename}.log"

# Check for Dependencies
# -----------------------------------
# Arrays containing package dependencies needed to execute this script.
# The script will fail if dependencies are not installed.  For Mac users,
# most dependencies can be installed automatically using the package
# manager 'Homebrew'.  Mac applications will be installed using
# Homebrew Casks. Ruby and gems via RVM.
# -----------------------------------
homebrewDependencies=()
caskDependencies=()
gemDependencies=()

# Exectute Teamcity step
#-------------------------------------
#
function ExecuteStep() {
  local "${@}"
  echo "##teamcity[compilationStarted compiler='$title']"
  debug "Executing command => $command $args"
  set +o errexit
  (
    cd "$workingdirectory"
    errormessage=$(eval "$command $args 2>&1 | tee /dev/stderr")
  )
  rv=$?
  [[ "$rv" -ne 0 ]] && {
    echo "##teamcity[message text='"Erreur Lors de la Step :"  $command  $args' status='ERROR']"
    echo "##teamcity[message text='"$errormessage"' status='ERROR']"
    exit $rv
  }

  echo "##teamcity[compilationFinished compiler='$title']"
  echo -n
  set -o errexit
}

# Deploy .net core application
#-----------------------------
#
function deploy() {
  local "${@}"
  # Generate app package
  ExecuteStep title="Dotnet Core publish" command="dotnet publish" workingdirectory=$workingdirectory configuration=$configuration args="-o $tmpDir/out"
  # Compress archive
  # Upload archive to S3
  # Create AMI
  # Update paramters.json file with the new Ami id
  # Package Cloud Formation stack
  # OctoPush
  # OctoRelease
}

# function PackageUpload ($archive, $key) {
 
#     Write-Host Write-S3Object -Region eu-west-1 -BucketName $bucketName -File $archive -Key $key -Verbose
#     Write-S3Object -Region eu-west-1 -BucketName $bucketName -File $archive -Key $key -Verbose
# }

function mainScript() {
  ############## Begin Script Here ###################
  ####################################################
  debug "buildversion = $buildversion"
  debug "configuration = $configuration"
  debug "enablenpm = $enablenpm"
  debug "workingdirectory = $workingdirectory"
  echo -n

  ####################################################
  ############### End Script Here ####################
  [[ "$enabledeployment" == "true" ]] && deploy workingdirectory=$workingdirectory configuration=$configuration 
}

############## Begin Options and Usage ###################

# Print usage
usage() {
  echo -n "${scriptName} [OPTION]... [FILE]...

This is build script allow the CICD for .net core application on AWS platform.

 ${bold}Options:${reset}
  -c, --configuration          Configuration build for .net application
  -w, --workingdirectory       Working directory
      --buildversion           Build application version
      --octopusenvironment     Octopus environment
      --octopuschannel)        Octopus channel
      --octopusproject)        Octopus project
  -r, --releasenotes)          Releasenotes
  -b, --branch)                Branch
  -n, --enablenpm)             Enable npm
      --enablesonar)           Enable sonar
  -p, --enabledeployment)      Enable deployment
  -f, --force                  Skip all user interaction.  Implied 'Yes' to all actions.
  -q, --quiet                  Quiet (no output)
  -l, --log                    Print log to file
  -s, --strict                 Exit script with null variables.  i.e 'set -o nounset'
  -v, --verbose                Output more information. (Items echoed to 'verbose')
  -d, --debug                  Runs script in BASH debug mode (set -x)
  -h, --help                   Display this help and exit
      --version                Output version information and exit
"
}

# Iterate over options breaking -ab into -a -b when needed and --foo=bar into
# --foo bar
optstring=h
unset options
while (($#)); do
  case $1 in
  # If option is of type -ab
  -[!-]?*)
    # Loop over each character starting with the second
    for ((i = 1; i < ${#1}; i++)); do
      c=${1:i:1}

      # Add current char to options
      options+=("-$c")

      # If option takes a required argument, and it's not the last char make
      # the rest of the string its argument
      if [[ $optstring == *"$c:"* && ${1:i+1} ]]; then
        options+=("${1:i+1}")
        break
      fi
    done
    ;;

  # If option is of type --foo=bar
  --?*=*) options+=("${1%%=*}" "${1#*=}") ;;
  # add --endopts for --
  --) options+=(--endopts) ;;
  # Otherwise, nothing special
  *) options+=("$1") ;;
  esac
  shift
done
set -- "${options[@]}"
unset options

# Print help if no arguments were passed.
# Uncomment to force arguments when invoking the script
# [[ $# -eq 0 ]] && set -- "--help"

# Read the options and set stuff
while [[ $1 == -?* ]]; do
  case $1 in
  -h | --help)
    usage >&2
    safeExit
    ;;
  --version)
    echo "$(basename $0) ${version}"
    safeExit
    ;;
  -c | --configuration)
    shift
    configuration=${1:-Release}
    ;;
  -w | --workingdirectory)
    shift
    workingdirectory=${1}
    ;;
  --buildversion)
    shift
    buildversion=${1:-1.0.0}
    ;;
  --octopusenvironment)
    shift
    octopusenvironment=${1:-Recette}
    ;;
  --octopuschannel)
    shift
    octopuschannel=${1}
    ;;
  --octopusproject)
    shift
    octopusproject=${1}
    ;;
  -r | --releasenotes)
    shift
    releasenotes=${1}
    ;;
  -b | --branch)
    shift
    branch=${1:-master}
    ;;
  -n | --enablenpm)
    shift
    enablenpm=true
    ;;
  --enablesonar)
    shift
    enablesonar=true
    ;;
  -p | --enabledeployment)
    shift
    enabledeployment=true
    ;;
  #-u|--username) shift; username=${1} ;;
  #-p|--password) shift; echo "Enter Pass: "; stty -echo; read PASS; stty echo;
  #  echo ;;
  -v | --verbose) verbose=true ;;
  -l | --log) printLog=true ;;
  -q | --quiet) quiet=true ;;
  -s | --strict) strict=true ;;
  -d | --debug) debug=true ;;
  -f | --force) force=true ;;
  --endopts)
    shift
    break
    ;;
  *) die "invalid option: '$1'." ;;
  esac
  shift
done
# Store the remaining part as arguments.
args+=("$@")

############## End Options and Usage ###################

#Init default value
configuration=${configuration:-Release}
buildversion=${buildversion:-1.0.0}
octopusenvironment=${buildversion:-Recette}
enablenpm=${enablenpm:-false}
enablesonar=${enablesonar:-false}
enabledeployment=${enabledeployment:-false}
workingdirectory=${workingdirectory:-$scriptPath}

# ############# ############# #############
# ##       TIME TO RUN THE SCRIPT        ##
# ##                                     ##
# ## You shouldn't need to edit anything ##
# ## beneath this line                   ##
# ##                                     ##
# ############# ############# #############

# Trap bad exits with your cleanup function
trap trapCleanup EXIT INT TERM

# Set IFS to preferred implementation
IFS=$'\n\t'

# Exit on error. Append '||true' when you run the script if you expect an error.
set -o errexit

# Run in debug mode, if set
if ${debug}; then set -x; fi

# Exit on empty variable
if ${strict}; then set -o nounset; fi

# Bash will remember & return the highest exitcode in a chain of pipes.
# This way you can catch the error in case mysqldump fails in `mysqldump |gzip`, for example.
set -o pipefail

# Invoke the checkDependenices function to test for Bash packages.  Uncomment if needed.
# checkDependencies

# Run your script
mainScript

# Exit cleanlyd
safeExit
