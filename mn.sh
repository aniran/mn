#!/usr/bin/env bash

# shellcheck disable=SC2046,SC2015,SC1090
function init_imports () {
    CMD_READLINK=$(readlink --version &>/dev/null && echo 'readlink -e' || echo 'stat -f "%Y"')
    APP_HOME=$(dirname $([ -L "$0" ] && $CMD_READLINK "$0" || ls "$0"))
    APP_HOME="${APP_HOME#\"}"

    source "$APP_HOME"/script_ctl.src
    source "$APP_HOME"/fmt_font.src    
}

function fn_file_exists () { [ -f "$1" ] || msg_quit "$1: not found."; }

function get_param () {
    local param loaded_param file

    param="$1"; file="$2"
    fn_file_exists "$file"
    loaded_param=$(grep "$param" "$file" 2>/dev/null | cut -d ' ' -f 2)
    [ -n "$loaded_param" ] && echo "$loaded_param"
}

init_imports

CONFIG_FILE="$APP_HOME"/config
GIT_LATEST_PULL="$APP_HOME"/.git_latest_pull
DEFAULT_GIT_URL_MSG=INSERT_CLONE_URL
GIT_MAJOR=$(cut -d . -f 1 <<<$(git --version | awk '{print $3}'))
MD5=$(type -t md5sum &>/dev/null && echo md5sum || echo md5)
FS_ENC_TAG=1.4.2
CMD_ENCRYPT="$APP_HOME"/encrypt.sh

for ii in "$MD5" git openssl; do
    type -t "$ii" &>/dev/null || msg_quit "Missing dependency: $ii"
done

function fn_validate_alnum () {
    grep -q -E '^[[:alnum:]]+$' <<<"$1" || msg_quit "Argument '$1' should contain alpha-numeric characters"
}

function fn_encryption () {
    [ ! -f "$CMD_ENCRYPT" ] || [ ! -x "$CMD_ENCRYPT" ] && msg_quit "Fail checking $CMD_ENCRYPT, please try running 'mn install'"
    
    local enc_command file_in
    enc_command="$1"
    file_in="$2"

    [ ! -f "$file_in" ] && msg_quit "Error opening $file_in"

    if grep -q -E '^[de]$' <<<"$enc_command"; then
        "$CMD_ENCRYPT" -"${enc_command}" -i "$file_in" -p $(read -s -p "Password: " && echo "$REPLY" ) 1>/dev/null
        echo -e "\n"
    else
        msg_quit "Encryption command not found: '$enc_command'" 
    fi
}

function fn_git () { 
    local operational_dir
    if [ -d "$1" ]; then
        operational_dir="$1"
        shift
    else
        operational_dir="$DATA_DIR" 
    fi

    cd "$operational_dir" && git $* && cd - &>/dev/null
}

function fn_check_latest_pull () {
    local secs_latest_pull
    [ ! -f "$GIT_LATEST_PULL" ] && echo "0" > "$GIT_LATEST_PULL" 
    secs_latest_pull=$(( $(date +"%s") - $(cat "$GIT_LATEST_PULL" ) ))
    [ "$secs_latest_pull" -gt "$GIT_PULL_INTERVAL" ] \
    && fn_git pull \
    && echo $(date +"%s") > "$GIT_LATEST_PULL" 
}

if [ -f "$CONFIG_FILE" ]; then
    DATA_DIR=$(get_param 'data_dir' "$CONFIG_FILE" )
    GIT_REPO=$(get_param 'git_repo' "$CONFIG_FILE" )
    GIT_PULL_INTERVAL=$(( $(get_param 'pull_hours_interval' "$CONFIG_FILE" ) * 3600 ))
    
    if [ "$GIT_REPO" = "$DEFAULT_GIT_URL_MSG" ]; then
        msg_quit "Please specify your git_repo from $CONFIG_FILE"
    elif [ -d "$DATA_DIR" ] && cd "$DATA_DIR" && git status &>/dev/null && cd - &>/dev/null; then
        fn_check_latest_pull
    else
        mkdir -p "$DATA_DIR" &>/dev/null
        [ "$(ls -A $DATA_DIR)" ] && msg_quit "$DATA_DIR is not empty, cant proceed."
        echo "Cloning $GIT_REPO to $DATA_DIR"
        cd "$DATA_DIR" \
        && git clone "$GIT_REPO" "$DATA_DIR" \
        && cd - &>/dev/null \
        && echo "done." 
        echo $(date +"%s") > "$GIT_LATEST_PULL" 
        read -n1 -p "Press any key to continue..."
    fi
else
    echo "Creating config file"
    echo -e "\
# Storage for notes and tags.\n\
data_dir $HOMEDIR/var/$CMD_NAME\n\
\n# Github repo URL to backup your notes.\n\
git_repo $DEFAULT_GIT_URL_MSG\n\
\n# Script wont do a git pull again until we are over this many hours from latest pull.\n\
pull_hours_interval 24" > $CONFIG_FILE \
    && echo "Done. Edit $CONFIG_FILE to setup 'git_repo' URL and 'data_dir' path."
    exit 0
fi

NOTES_DIR="$DATA_DIR"/notes ; mkdir -p "$NOTES_DIR" 2>/dev/null
TAGS_DIR="$DATA_DIR"/tags   ; mkdir -p "$DATA_DIR" 2>/dev/null
CMD_TIME="$DATA_DIR"/$CMD_TIME
UNIQUE_TAGS_FILE="$DATA_DIR"/unique_tags
INDEX_TRUC_FILE="$DATA_DIR"/index_truncate
MODE_USR_RW="0600"
MODE_USR_RWX="0700"

function ff_topic    () { echo $(fmt_font bold  color white   "$1"); }
function ff_index    () { echo $(fmt_font color light_yellow  "$1"); }
function ff_content  () { echo $(fmt_font color dark_gray    "$1"); }
function ff_normal   () { echo $(fmt_font color white        "$1"); }
function ff_tags     () { echo $(fmt_font color cyan          "$1"); }
function ff_sel_tags () { echo $(fmt_font color light_cyan    "$1"); }
function ff_protectd () { echo $(fmt_font bgcolor dark_gray color black "$1"); }

function fn_get_filepath_id () {
    local id file_dir entry_file

    id="$1"
    file_dir="$2"

    [ -z "$id" ] && msg_quit "<ID> argument cannot be empty."
    [ ! -d "$file_dir" ] && msg_quit "Directory path not found: $file_dir"

    entry_file=$(ls "$file_dir"/$id*)

    [ $(wc -l <<<"$entry_file") -gt 1 ] && msg_quit "More than 1 file found for id=$id"
    [ ! -f "$entry_file" ]              && msg_quit "File not found: $entry_file" 

    echo "$entry_file"
} 

function fn_preview_file () { 
    local file_in
    file_in="$1"

    [ ! -f "$file_in" ] && msg_quit "File not found: $file_in"

    if [ $(cut -d '.' -f 2 <<<"$file_in") = "enc" ]; then
        echo $(ff_protectd "Encrypted")
    else
        echo -e $(ff_content "$(head -c $TERM_COLS $file_in 2>/dev/null)")
    fi
}

function update_unique_tags () {
    cat "$TAGS_DIR"/* \
    | tr ' ' '\n' \
    | sort \
    | uniq > "$UNIQUE_TAGS_FILE"
}

function update_index_truncate () {
    local len=1

    function dup_notes_entries () {
        for ii in $(ls -1 "$NOTES_DIR"); do echo ${ii::$1}; done
    }

    while [ $( dup_notes_entries "$len" | sort | uniq -d | wc -l) -gt 0 ]; do
        len=$(( len + 1 ))
    done

    echo "$len" > "$INDEX_TRUC_FILE"
}

function commit_push () { 
    local ftz
    ftz=$(date +"%F %T %Z")

    if [ "$(fn_git status --porcelain=v1 2>/dev/null | wc -l)" -gt 0 ]; then
        echo "$ftz - $CMD_NAME backup." > "$CMD_TIME"
        fn_git add .
        fn_git commit -a -F "$CMD_TIME"
        fn_git push 
        rm "$CMD_TIME"
    fi
}

function force_pull () {
    echo "0" > "$GIT_LATEST_PULL" && fn_check_latest_pull
}

USAGE="$(ff_topic NAME)\n\
    ${CMD_NAME} - A note-keeping script written in bash.\n\
\n$(ff_topic SYNTAX)\n\
    $CMD_NAME {new|grep|list|edit|rm}
" 
function print_usage () { echo -e "$USAGE"; }

function set_param () {
    local param file values

    param=$1 ; shift
    file=$1  ; shift
    values="$*"

    fn_file_exists "$file"

    if grep -q "$param" "$file"; then
        sed -i .tmp "s/^${param} .*/${param} ${values}/g" "$file" 
        rm ${file}.tmp
    else
        echo "$param $values" >> "$file"
    fi
}

function new_note () {
    local arg1 mode_encrypt mode_import import_file new_tags new_md5 new_file_path
    arg1="$1"

    while [ "${arg1::1}" = ":" ]; do
        case $arg1 in
            :enc*) mode_encrypt=T ;;
            :imp*) mode_import=T  ;;
        esac
        shift 
        arg1="$1"
    done
    
    if [ "$mode_import" ]; then
        import_file="$arg1" 
        [ ! -f "$import_file" ] && msg_quit "Error while reading file '$import_file'"
        shift
    fi

    new_tags="$*"

    [ -z "$new_tags" ] && echo "Allowed characters: Uppercase and lowercase letters, numbers, dash '-', underscore '_', dot '.'"

    while [ -z "$new_tags" ]; do 
        read -p "Tags: " new_tags
        new_tags=$(tr -dc '[._ [:alnum:]-]' <<<"$new_tags")
    done

    [ "$mode_import" ] && install -m "$MODE_USR_RW" "$import_file" "$CMD_TIME" 

    vim "$CMD_TIME" 

    new_md5=$($MD5 $CMD_TIME | awk '{print $1}') \
    && new_file_path=$NOTES_DIR/$new_md5 \
    && mv "$CMD_TIME" "$new_file_path" 

    if [ "$mode_encrypt" ]; then
        fn_encryption e "$new_file_path" \
        && rm "$new_file_path" \
        && new_file_path="$new_file_path".enc \
        && new_md5="$new_md5".enc
    fi

    echo "Saving note $(ff_index $new_md5): $(ff_tags $new_tags)" \
    && echo "$new_tags" > "$TAGS_DIR/$new_md5" \
    && update_unique_tags \
    && update_index_truncate 
    
    commit_push
}

function grep_note () {
    [ -z "$1" ] && return 0
    local whole_query pattern files_list index_trunc files_list id

    whole_query="$*"
    pattern="${whole_query// /\\|}"
    files_list="$(find $NOTES_DIR -type f)"
    index_trunc=$(cat "$INDEX_TRUC_FILE")

    for ii in "$whole_query"; do
        [ -z "$files_list" ] && return
        files_list="$(grep "$ii" -l "$files_list")" 
    done

    for ii in "$files_list"; do
        id=$(basename "$ii")
        echo -e $(ff_index ${id::$index_trunc})": "$(ff_tags "$(cat $TAGS_DIR/$id)")
        grep -h --color=auto "$pattern" "$ii"
        echo ""
    done
}

function grep_by_tags () {
    [ -z "$1" ] && echo -e $(ff_tags "$(cat $UNIQUE_TAGS_FILE | paste -s -)") && return 0
    local whole_query pattern files_list files_list index remaining_tags

    whole_query="$*"
    pattern="${whole_query// /\\|}"
    files_list="$(find $TAGS_DIR -type f)"

    for ii in "$whole_query"; do
        [ -z "$files_list" ] && return
        files_list="$(grep $ii -l $files_list)" 
    done

    for ii in "$files_list"; do
        index=$(basename "$ii")
        remaining_tags=$(cat "$ii" | sed "s/$pattern//g")
        echo -e $(ff_index $index)":"$(ff_sel_tags "$whole_query")" "$(ff_tags "$remaining_tags")
        fn_preview_file "$ii"
        echo ""
    done
}

function list_notes () {
    local wc_tags_dir index_trunc tags

    wc_tags_dir=$(ls -1 "$TAGS_DIR" | wc -l)

    [ "$wc_tags_dir" = "0" ] && msg_quit "$TAGS_DIR is empty."

    index_trunc=$(cat "$INDEX_TRUC_FILE")

    echo ""

    for ii in $(ls -1 "$NOTES_DIR"); do
        id_trunc="${ii::$index_trunc}"
        tags=$(cat "$TAGS_DIR/$ii")
        echo "$(ff_index $id_trunc): "$(ff_tags "$tags")
        fn_preview_file "$NOTES_DIR/$ii"
    done
    echo ""
}

function edit_note () {
    local id enable_encrypt disable_encrypt change_tags old_note_md5 old_tags new_tags 

    id="$1"

    while [ "${id::1}" = ":" ]; do
        case $id in
            :enc*) enable_encrypt=T  ; unset disable_encrypt ;;
            :dec*) disable_encrypt=T ; unset enable_encrypt  ;;
            :tag*) change_tags=T                             ;;
            *) msg_quit "Mode not found: '$id'"                    ;;
        esac
        shift 
        id="$1"
    done

    fn_validate_alnum "$id"

    fn_get_filepath_id "$id" "$NOTES_DIR" 1>"$CMD_TIME" && read note_file_path < "$CMD_TIME" 
    fn_get_filepath_id "$id" "$TAGS_DIR"  1>"$CMD_TIME" && read tags_file_path < "$CMD_TIME"

    rm "$CMD_TIME"

    old_note_md5=$(basename "$note_file_path")
    old_tags=$(cat "$tags_file_path")
    new_tags=""
    
    if [ "$change_tags" ]; then
        if [ "$BASH_V" -gt "3" ]; then
            while [ -z "$new_tags" ]; do read -e -i "$old_tags" -p "Tags: " new_tags; done
        else
            echo -e "Current tags: "$(ff_tags "$old_tags")
            read -p "Type new tags or [ENTER] to keep the current: " new_tags
            [ -z "$new_tags" ] && new_tags="$old_tags"
        fi
        if [ ! "$new_tags" = "$old_tags" ]; then
            echo "$new_tags" > "$tags_file_path"
            update_unique_tags
        fi
    fi

    if grep -q -E '\.enc$' <<<"$note_file_path"; then
        fn_encryption d "$note_file_path"        \
        && rm "$note_file_path"                   \
        && note_file_path="${note_file_path%.enc}" \
        && file_was_encrypted=".enc"       || msg_quit "Error while decrypting $note_file_path"
    fi

    vim "$note_file_path" || msg_quit "Error while editing $note_file_path"

    [ "$disable_encrypt" ] && unset file_was_encrypted

    local file_was_encrypted

    if [ "$file_was_encrypted" ] || [ "$enable_encrypt" ]; then
        fn_encryption e "$note_file_path" \
        && mv "${note_file_path}".enc "$note_file_path" \
        && file_was_encrypted=".enc" 
    fi

    local new_md5
    new_md5=$("$MD5" "$note_file_path" | awk '{print $1}') 

    mv "$note_file_path" "$NOTES_DIR/${new_md5}${file_was_encrypted}" 2>/dev/null
    mv "$tags_file_path" "$TAGS_DIR/${new_md5}${file_was_encrypted}" 2>/dev/null

    update_index_truncate 
}

function cat_note () {
    local id
    id="$1"

    [ -z "$id" ] && msg_quit "USAGE: $CMD_NAME show <ID>"

    fn_get_filepath_id "$id" "$NOTES_DIR" 1>"$CMD_TIME"
    local note_file
    note_file=$(cat "$CMD_TIME") && rm "$CMD_TIME"

    grep -q -E '.enc' <<<"$note_file" \
    && fn_encryption d "$note_file"    \
    && cat "${note_file%.enc}"          \
    && rm "${note_file%.enc}"           || cat "$note_file"
}

function rm_note () {
    local id
    id="$1"
    [ -z "$id" ] && msg_quit "USAGE: $CMD_NAME rm <ID>"

    fn_get_filepath_id "$id" "$NOTES_DIR" 1>"$CMD_TIME"
    local note_file
    note_file=$(cat "$CMD_TIME")

    fn_get_filepath_id "$id" "$TAGS_DIR" 1>"$CMD_TIME"
    local tag_file
    tag_file=$(cat "$CMD_TIME")

    rm "$CMD_TIME"

    echo -e "Files about to be deleted:\n\n$note_file\n$tag_file\n"

    if read -p "Do you want to proceed ? [y/n] " && grep -q -E '^[Yy]([Ee][Ss])?$' <<<"$REPLY"; then
        rm -f "$note_file" "$tag_file" \
        && update_unique_tags \
        && update_index_truncate \
        && commit_push \
        && echo "" \
        && list_notes \
        && echo "Record $(ff_index $id) was deleted."
    fi
}

function fn_install () {
    local complete_src complete_src_basename encrypt_script 

    complete_src="$CMD_REAL_DIR/complete_${CMD_NAME}.src"
    complete_src_basename=$(basename "$complete_src")
    encrypt_script="$CMD_REAL_DIR/submodules/fastsitephp/scripts/shell/bash/encrypt.sh"

    [ -d ~/init_source ] \
    && [ -f "$complete_src" ] \
    && ln -f -s "$complete_src" ~/init_source/"$complete_src_basename"

    [ -d ~/bin ] \
    && ln -f -s "$CMD_REAL_PATH" ~/bin/"$CMD_BASENAME" 

    local encrypt_script_dir
    encrypt_script_dir=$(dirname "$encrypt_script")

    if [ -d "$encrypt_script_dir" ]; then
        fn_git "$encrypt_script_dir" submodule init
        fn_git "$encrypt_script_dir" submodule update
        fn_git "$encrypt_script_dir" checkout "$FS_ENC_TAG"
        cp "$encrypt_script" "$CMD_REAL_DIR"
    else
        msg_quit "Error checking out $encrypt_script_dir"
    fi

    chmod "$MODE_USR_RWX" "$CMD_ENCRYPT"
}

function comptag () {
    local intersect pattern
    [ -z "$1" ] && cat "$UNIQUE_TAGS_FILE" | paste -s - && return
    intersect="$*"
    pattern=$(sed -E 's/([_[:alnum:].-]+)/\\<\1\\>/g' <<<"$intersect" | sed 's/ /\\|/g')
    echo "pattern=$pattern"
    grep -v "$pattern" "$UNIQUE_TAGS_FILE" | paste -s -
}

case $1 in
    list)    list_notes               ;;
    install) fn_install               ;;
    save)    commit_push              ;;
    load)    force_pull               ;;
    --ctag)  shift; comptag $*        ;;
    new)     shift; new_note $*       ;;
    grep)    shift; grep_note $*      ;;
    tag*)    shift; grep_by_tags $*   ;;
    edit)    shift; edit_note "$@"    ;;
    rm)      shift; rm_note $1        ;;
    show)    shift; cat_note $1       ;;
    *)       print_usage              ;;
esac
#14
