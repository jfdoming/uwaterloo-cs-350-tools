#!/usr/bin/env bash

: <<'END'
MIT License
Copyright (c) 2020 Julian Dominguez-Schatz

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
END

# Enable more warnings for easier debugging.
set -u
set -o pipefail

# Put utilities useful in the test-checking code here.
s2ms() {
    echo $(perl -E "say $1 * 1000.0")
}


# Change these to configure the script.
CS350_ROOT=~/cs350-os161/root # The folder containing the compiled kernel.
REQUIRE_DOCKER=1 # Whether to require running the script inside a docker container.

# Change these to support a new test.
VALID_TESTS=(sy1 sy2 sy3 uw1 sp3)
determine_if_failed() {
    # $1 is the abbreviated test output.
    # $2 is the full test output, including startup messages.
    # $3 is the test name being run.
    # $4+ are any test arguments.
    # Return 0 if the test failed and 1 if it passed.

    # Fail on any panics, regardless of the test.
    if [ -n "$(echo "$2" | grep -i "panic")" ]; then
        return 0
    fi

    # Perform test-specific logic. Each entry which you add here should
    #  correspond to an entry in the VALID_TESTS array above.
    case "$3" in
        sy1)
            if [ -z "$(echo "$1" | grep "broken: ok")" ]; then
                return 0
            fi
            ;;
        sy3)
            # Change the delimiter so we can iterate over lines of the abbreviated output.
            IFS=$'\n'

            # We expect 32 threads printed in reverse order, 5 times in a row.
            local i=1
            local j=31
            for line in $1; do
                # Skip irrelevant lines in the output.
                if [ -n "$(echo $line | grep 'cleanitems\|done\|Starting\|32 threads should print')" ]; then
                    continue
                fi

                if ! [ "$line" = "Thread $j" ]; then
                    # Don't forget to reset the delimiter when we finish.
                    unset IFS

                    return 0
                fi
                j=$((j-1))
                if [ $j -eq -1 ]; then
                    i=$((i+1))
                    j=$((j+32))
                fi
            done

            # Don't forget to reset the delimiter when we finish.
            unset IFS

            # Make sure we ran precisely the number of times we wanted to.
            if [ $i -ne 6 ] || [ $j -ne 31 ]; then
                return 0
            fi
            ;;
        sp3)
            # Give the variables names locally.
            if [ "$#" -eq 3 ]; then
                # These default values are taken directly from the source code.
                local n=10
                local k=100
                local i=1
                local t=1
                local b=0
            else
                local n=$4
                local k=$5
                local i=$6
                local t=$7
                local b=$8
            fi

            local lines="$(echo "$1" | grep vehicles | sed "s/[^0-9. ]//g")"
            IFS=$'\n'
            lines=($lines)
            unset IFS

            local overall_stats=(${lines[-1]})
            local total_time="${overall_stats[0]}"
            total_time=$(s2ms $total_time)

            # These rules are hard-coded because they were provided in the hints guide.
            echo "WARNING: test not implemented!" >&2

            # Efficiency
            # TODO implement this

            # Fairness
            # TODO implement this

            ;;
        *)
            # For all other tests, assume that a "fail" in the output means
            #  the test failed.
            if [ -n "$(echo "$1" | grep -i fail)" ]; then
                return 0
            fi
            ;;
    esac

    # If we reach this point, assume the test passed.
    return 1
}

##### SCRIPT IMPLEMENTATION #####

# Some utility functions for use later on.
usage() {
    # Prints usage information; useful for error and help messages.

    if [ "$#" -ne 0 ]; then
        echo "$1"
        echo
    fi

    echo "Usage:    ./run-test.sh [-n <num_times_to_run>]"
    echo "                        [-c <sequence_of_cores_to_use>]"
    echo "                        [-l <log_file>]"
    echo "                        [-L <full_log_file>]"
    echo "                        [-v]"
    echo "                        [-f]"
    echo "                        <test_name>"
    echo "                        [...test_args]"
    echo "Examples: ./run-test.sh sy1                 # Run the semaphore test 100 times on 1 core."
    echo "          ./run-test.sh -n 50 sy1           # Run the semaphore test 50 times on 1 core."
    echo "          ./run-test.sh -c 4 sy1            # Run the semaphore test 100 times on 4 core."
    echo "          ./run-test.sh -n 50 -c 1,2,4 sy1  # Run the semaphore test 100 times on each of 1, 2 and 4 cores."
    echo "          ./run-test.sh -n 5 -v sy1         # Run the semaphore test 5 times on 1 core, printing the output for each instance."
    echo "          ./run-test.sh -f my_fake_test     # Force-run the given test 100 times on 1 core."
    echo "          ./run-test.sh -l file.txt sy1     # Run the semaphore test 100 times on 1 core, logging the output to file.txt for each instance."
    echo "          ./run-test.sh -L file.txt sy1     # Run the semaphore test 100 times on 1 core, logging the full output (including startup messages)"
    echo "                                            #  to file.txt for each instance."
}
pluralize() {
    # Chooses between two strings depending on whether the plural form should be used.

    if [ "$1" -eq 1 ]; then
        echo -ne "$2"
    else
        echo -ne "$3"
    fi
}
listify() {
    # Prints out the given list in the format "1, 2 and 3".

    els=("$@")
    if [ "${#els[@]}" -eq 0 ]; then
        return
    fi

    if [ "${#els[@]}" -eq 1 ]; then
        echo -n "$els"
        return
    fi

    for c in "${els[@]::${#els[@]}-2}"; do
        echo -n "$c, "
    done
    echo -n "${els[-2]} "
    echo -n "and ${els[-1]}"
}

# Display an error if we're not running inside a Docker container and we should be.
if [ "$REQUIRE_DOCKER" -eq 1 ] && command -v docker > /dev/null && ! grep docker /proc/1/cgroup -qa; then
  echo 'ERROR: Please run this script inside the interactive CS350 shell.'
  exit 1
fi

count=100
cores=(1)
verbose=0
force_run=0
log_file=
full_log_file=

while getopts ":n:c:l:L:vfh" o; do
    case "${o}" in
        n)
            count=${OPTARG}
            if [ -z "$count" ]; then
                usage "ERROR: Please specify the number of instances to run."
                exit 1
            fi
            if ! [[ $count =~ ^[\-0-9]+$ ]] || (( count <= 0)); then
                usage "ERROR: The number of instances must be a positive integer."
                exit 1
            fi
            ;;
        c)
            cores=${OPTARG}
            if [ -z "$cores" ]; then
                usage "ERROR: Please specify a non-empty list of cores to run on."
                exit 1
            fi
            cores=($(echo "$cores" | sed "s/^,//" | sed "s/,$//" | sed "s/[[:space:]]*,[[:space:]]*/\n/g" | sed "s/[[:space:]]\+/ /g" | awk '!visited[$0]++'))
            ;;
        l)
            log_file=${OPTARG}
            if [ -z "$log_file" ]; then
                usage "ERROR: Please specify the path to a file to log to."
                exit 1
            fi
            log_file=$(realpath "$log_file")
            if ! touch $log_file; then
                usage "ERROR: Write permission denied for the specified log file."
                exit 1
            fi
            ;;
        L)
            full_log_file=${OPTARG}
            if [ -z "$full_log_file" ]; then
                usage "ERROR: Please specify the path to a file to log to."
                exit 1
            fi
            full_log_file=$(realpath "$full_log_file")
            if ! touch $full_log_file; then
                usage "ERROR: Write permission denied for the specified log file."
                exit 1
            fi
            ;;
        v)
            verbose=1
            ;;
        f)
            force_run=1
            ;;
        h)
            usage
            exit
            ;;
        \:)
            case "$OPTARG" in
                n)
                    usage "ERROR: Please specify the number of instances to run."
                    ;;
                c)
                    usage "ERROR: Please specify a non-empty list of cores to run on."
                    ;;
                L)
                    ;&
                l)
                    usage "ERROR: Please specify the path to a file to log to."
                    ;;
                *)
                    usage "ERROR: Argument missing for option -$OPTARG."
                    ;;
            esac
            exit 1
            ;;
        *)
            OPTIND=$((OPTIND))
            usage "ERROR: Unrecognized option -$OPTARG."
            exit 1
            ;;
    esac
done
shift $((OPTIND-1))

if [ "$#" -eq 0 ]; then
    usage "ERROR: Please specify a test to run."
    exit 1
fi

valid_test_found=0
for t in "${VALID_TESTS[@]}"; do
    if [ "$1" = "$t" ]; then
        valid_test_found=1
    fi
done
if [ "$valid_test_found" -eq 0 ]; then
    if [ "$force_run" -eq 1 ]; then
        echo "WARNING: running a test which has not yet been added to this script may result in false passes."
        echo "The following $(pluralize "${#VALID_TESTS[@]}" "test has" "tests have") been added: $(listify "${VALID_TESTS[@]}")."
    else
        echo "ERROR: Invalid test: $1."
        echo "The following $(pluralize "${#VALID_TESTS[@]}" "test is" "tests are") valid: $(listify "${VALID_TESTS[@]}")."
        exit 1
    fi
fi

# set up the simulator run
cd $CS350_ROOT

# Can't run two tests at once, sadly.
if [ -f "$CS350_ROOT/sys161.conf.old" ]; then
    echo "WARNING: backup config file detected. This can occur:"
    echo " - If you try to run multiple instances of this script in parallel. (This is not supported)."
    echo " - If you kill the script without giving it a chance to clean up (CTRL-C should work fine)."
    echo "To recover from this, you can either:"
    echo " - Manually merge \"sys161.conf\" and \"sys161.conf.old\" in the directory \"$CS350_ROOT/\" and then delete the backup file."
    echo " - Request this script to delete the backup file directly."
    read -rsn 1 -p "Would you like to delete the backup now? This script will exit otherwise. [yYnN] "
    echo
    if [[ "$REPLY" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        rm $CS350_ROOT/sys161.conf.old
        if [ -f "$CS350_ROOT/sys161.conf.old" ]; then
            echo "ERROR: Failed to delete the backup file."
            exit 1
        fi
    else
        exit 1
    fi
fi

valid_cores=$(sed -ne "s/^.*  cpus=//p" ./sys161.conf)
if [ -z "$valid_cores" ]; then
    echo "There are no valid core counts, please add one."
    exit 1
fi
valid_cores=($valid_cores)

# O(n^2), but I'm not too worried since the # of core counts should always be very small.
invalid_cores=()
for core in "${cores[@]}"; do
    found_valid_core=0
    for valid_core in "${valid_cores[@]}"; do
        if [ "$core" = "$valid_core" ]; then
            found_valid_core=1
            break
        fi
    done
    if [ "$found_valid_core" -eq 0 ]; then
        invalid_cores+=($core)
    fi
done
if [ "${#invalid_cores[@]}" -gt 0 ]; then
    echo "ERROR: The following core $(pluralize "${#invalid_cores[@]}" "count is" "counts are") invalid: $(listify "${invalid_cores[@]}")."
    echo "Valid core $(pluralize "${#valid_cores[@]}" "count" "counts") include: $(listify "${valid_cores[@]}")."
    exit 1
fi


# Check for reasonable testing values.
note_shown=0
if [ "$count" -lt 25 ]; then
    echo "NOTE: Be sure to run with a sufficiently high instance count to ensure the robustness of your code."
    note_shown=1
fi
if [ "${#cores[@]}" -eq 1 ]; then
    echo "NOTE: Be sure to run with both single- and multi-core setups to ensure the robustness of your code."
    note_shown=1
fi
if [ "$note_shown" -eq 1 ]; then
    echo
fi


# Make a backup of the configuration file.
cp $CS350_ROOT/sys161.conf $CS350_ROOT/sys161.conf.old
trap "{
    if [ -f $CS350_ROOT/sys161.conf.old ]; then
        cp $CS350_ROOT/sys161.conf.old $CS350_ROOT/sys161.conf;
        rm $CS350_ROOT/sys161.conf.old;
    fi
}" EXIT


# Wipe the log file to start over.
if [ -n "$log_file" ]; then
    > "$log_file"
fi
if [ -n "$full_log_file" ]; then
    > "$full_log_file"
fi


first=1
for core in ${cores[@]}; do
    if [ "$first" -eq 1 ]; then
        first=0
    else
        echo
        if [ -n "$log_file" ]; then
            echo "====================================================" >> "$log_file"
        fi
        if [ -n "$full_log_file" ]; then
            echo "====================================================" >> "$full_log_file"
        fi
    fi
    echo "Running $count $(pluralize "$count" "instance" "instances") on $core $(pluralize "$core" "core" "cores")..."

    if [ -n "$log_file" ]; then
        echo "$core $(pluralize "$core" "core" "cores"):" >> "$log_file"
    fi
    if [ -n "$full_log_file" ]; then
        echo "$core $(pluralize "$core" "core" "cores"):" >> "$full_log_file"
    fi

    sed -i "/^31[[:space:]]\+mainboard[[:space:]]\+ramsize=[^[:space:]]*[[:space:]]\+cpus=[^$core]/s/^/#/" ./sys161.conf
    sed -i "/^#31[[:space:]]\+mainboard[[:space:]]\+ramsize=[^[:space:]]*[[:space:]]\+cpus=[$core]/s/^#//" ./sys161.conf

    successes=0
    for i in $(seq $count); do
        if [ "$verbose" -ne 1 ] && [ "$successes" -gt 1 ]; then
            echo -ne $'\r'
        fi
        echo -ne "$(pluralize "$successes" $'\b \r' "")$successes $(pluralize "$successes" "instance" "instances") passed."

        if [ "$verbose" -eq 1 ]; then
            echo
            output=$(sys161 kernel "$@;q" 2>&1 | tee /dev/tty)
        else
            output=$(sys161 kernel "$@;q" 2>&1)
        fi
        result=$(echo "$output" | sed -n '/^OS\/161 kernel: /,/^Operation took /p;/^Operation took/q' | head -n -1 | tail -n +2)

        if [ -n "$log_file" ]; then
            echo "----------------------------------------------------" >> "$log_file"
            echo "$result" >> "$log_file"
        fi
        if [ -n "$full_log_file" ]; then
            echo "----------------------------------------------------" >> "$full_log_file"
            echo "$output" >> "$full_log_file"
        fi

        failure_output=$(determine_if_failed "$result" "$output" "$@")
        return_value=$?
        if [ "$return_value" -eq 0 ]; then
            # Failed!
            echo
            if [ "$verbose" -eq 0 ]; then
                if [ "$successes" -eq 1 ]; then
                    echo -n "The test failed after $successes instances! "
                else
                    echo -n "The test failed after $successes instances! "
                fi
                read -rsn 1 -p "Would you like to review the output? ([yY] = Yes, [fF] = Full, [nN] = No) "
                echo
                if [[ "$REPLY" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                    echo "$result"
                    if [ -n "$failure_output" ]; then
                        echo "$failure_output"
                    fi
                fi
                if [[ "$REPLY" =~ ^([fF][uU][lL][lL]|[fF])$ ]]; then
                    echo "$output"
                    if [ -n "$failure_output" ]; then
                        echo "$failure_output"
                    fi
                fi
            fi
            stty echo
            exit 1
        fi
        successes=$((successes+1))
    done

    stty echo
    echo -e $'\r'"All instances passed."
done
