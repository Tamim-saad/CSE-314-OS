#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 -i input_file.txt"
    exit 1
}

# Function to check if a string is a number
is_number() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

# Function to check if a command is available
check_command() {
    if ! command -v "$1" &>/dev/null; then
        echo "Error: $1 is not installed."
        exit 1
    fi
}

# Function to unarchive submissions
unarchive_submission() {
    local student_id="$1"
    local submission_file="$2"
    local archive_extension="${submission_file##*.}"

    mkdir -p "$student_id"
    case "$archive_extension" in
    zip) unzip -q "$submission_file" -d "$student_id" ;;
    rar) unrar x -o+ "$submission_file" "$student_id" >/dev/null ;;
    tar) tar -xf "$submission_file" -C "$student_id" ;;
    *) return 1 ;; # Unsupported format
    esac
}

# Function to compile and run code based on language
compile_and_run_code() {
    local student_id="$1"
    local language="$2"
    local output_file="$3"

    case "$language" in
    c)
        gcc "${student_id}.c" -o "$student_id" 2>error.log
        if [ $? -ne 0 ]; then
            return 1 # Compilation error
        fi
        ./"$student_id" >"$output_file" 2>&1
        ;;
    cpp)
        g++ "${student_id}.cpp" -o "$student_id" 2>error.log
        if [ $? -ne 0 ]; then
            return 1 # Compilation error
        fi
        ./"$student_id" >"$output_file" 2>&1
        ;;
    py)
        python3 "${student_id}.py" >"$output_file" 2>&1
        ;;
    sh)
        bash "${student_id}.sh" >"$output_file" 2>&1
        ;;
    *)
        return 1 # Unsupported language
        ;;
    esac
    return 0
}

# Function to process a single student's submission
process_submission() {
    local student_id="$1"
    local allowed_formats="$2"
    local use_archive="$3"
    local penalty_guidelines="$4"
    local penalty_unmatched="$5"
    local expected_output="$6"
    local plagiarism_file="$7"
    local plagiarism_penalty="$8"
    local total_marks="$9"

    local marks_deducted=0
    local remarks=""
    local submission_file=""
    local language=""
    local output_file="${student_id}_output.txt"

    # Check for archived submission or source file
    for format in zip rar tar; do
        if [ -f "${student_id}.${format}" ]; then
            submission_file="${student_id}.${format}"
            break
        fi
    done

    if [ "$use_archive" = "true" ] && [ -n "$submission_file" ]; then
        unarchive_submission "$student_id" "$submission_file"
        if [ $? -ne 0 ]; then
            remarks+="Unsupported archive format. "
            marks_deducted=$((marks_deducted + penalty_guidelines))
        fi
    elif [ -f "${student_id}.c" ] || [ -f "${student_id}.cpp" ] || [ -f "${student_id}.py" ] || [ -f "${student_id}.sh" ]; then
        mkdir -p "$student_id"
        mv "${student_id}."* "$student_id/"
    else
        remarks+="Submission not found. "
        marks_deducted=$((marks_deducted + penalty_guidelines))
        echo "$student_id,$total_marks,$marks_deducted,0,\"$remarks\"" >>marks.csv
        return
    fi

    # Check language and compile/run code
    for lang in c cpp py sh; do
        if [ -f "${student_id}/${student_id}.${lang}" ]; then
            language=$lang
            break
        fi
    done

    if [ -z "$language" ]; then
        remarks+="No supported language file found. "
        marks_deducted=$((marks_deducted + penalty_guidelines))
        echo "$student_id,$total_marks,$marks_deducted,0,\"$remarks\"" >>marks.csv
        return
    fi

    compile_and_run_code "$student_id" "$language" "$output_file"
    if [ $? -ne 0 ]; then
        marks_deducted=$((marks_deducted + penalty_guidelines))
        remarks+="Compilation/Execution error: $(cat error.log 2>/dev/null). "
    fi

    # Compare output
    if [ -f "$output_file" ] && ! diff "${student_id}/${output_file}" "$expected_output" >/dev/null; then
        marks_deducted=$((marks_deducted + penalty_unmatched))
        remarks+="Output mismatch. "
    fi

    # Check for plagiarism
    if grep -q "$student_id" "$plagiarism_file"; then
        local plagiarism_deduction=$((total_marks * plagiarism_penalty / 100))
        marks_deducted=$((marks_deducted + plagiarism_deduction))
        remarks+="Plagiarism detected. "
    fi

    # Calculate final marks
    local final_marks=$((total_marks - marks_deducted))
    final_marks=$((final_marks > 0 ? final_marks : 0))

    # Append to marks report
    echo "$student_id,$total_marks,$marks_deducted,$final_marks,\"$remarks\"" >>marks.csv

    # Move submission to appropriate directory
    if [ "$marks_deducted" -gt 0 ]; then
        mv "$student_id" issues/
    else
        mv "$student_id" checked/
    fi
}

# Main script logic

# Check for correct usage
if [ "$#" -ne 2 ] || [ "$1" != "-i" ]; then
    usage
fi

INPUT_FILE="$2"

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file not found."
    usage
fi

# Read input file with validation
mapfile -t input_lines <"$INPUT_FILE"
use_archive="${input_lines[0]}"
allowed_formats="${input_lines[1]}"
allowed_languages="${input_lines[2]}"
total_marks="${input_lines[3]}"
penalty_unmatched="${input_lines[4]}"
working_directory="${input_lines[5]}"
id_range="${input_lines[6]}"
expected_output="${input_lines[7]}"
penalty_guidelines="${input_lines[8]}"
plagiarism_file="${input_lines[9]}"
plagiarism_penalty="${input_lines[10]}"

# Validate numeric input
if ! is_number "$total_marks" || ! is_number "$penalty_unmatched" || ! is_number "$penalty_guidelines" || ! [[ "$plagiarism_penalty" =~ ^[0-9]+%$ ]]; then
    echo "Error: Invalid input format for numeric values."
    exit 1
fi

# Remove % from plagiarism_penalty and convert to integer
plagiarism_penalty="${plagiarism_penalty%\%}"

# Split ID range
read -r start_id end_id <<<"$id_range"

# Change to working directory
if [ ! -d "$working_directory" ]; then
    echo "Error: Working directory does not exist."
    exit 1
fi
cd "$working_directory" || exit 1

# Create output directories
mkdir -p "issues" "checked"

# Initialize marks.csv
echo "id,marks,marks_deducted,total_marks,remarks" >marks.csv

# Check if unrar is available for .rar files
check_command unrar

# Process each student submission
for ((id = start_id; id <= end_id; id++)); do
    student_id=$(printf "%07d" $id)
    process_submission "$student_id" "$allowed_formats" "$use_archive" "$penalty_guidelines" "$penalty_unmatched" "$expected_output" "$plagiarism_file" "$plagiarism_penalty" "$total_marks"
done

echo "Autograding complete. Check 'marks.csv' for results."
