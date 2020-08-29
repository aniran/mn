#!/usr/bin/env bash
#set -x
APP_HOME=$(dirname $([ -L "$0" ] && readlink $0 || ls $0))

source $APP_HOME/script_ctl.src
source $APP_HOME/fmt_font.src    

function fn_file_exists () { [ -f "$1" ] || msg_quit "$1: not found."; }

function get_param () {
    local param=$1; local file=$2
    fn_file_exists $file
    local loaded_param=$(grep $param $file 2>/dev/null | cut -d ' ' -f 2)
    [ -n "$loaded_param" ] && echo $loaded_param 
}

CONFIG_FILE=$APP_HOME/config
GIT_LATEST_PULL=$APP_HOME/.git_latest_pull
DEFAULT_GIT_URL_MSG=INSERT_CLONE_URL
GIT_MAJOR=$(cut -d . -f 1 <<<$(git --version | awk '{print $3}'))
MD5=$(type -t md5sum &>/dev/null && echo md5sum || echo md5)

for ii in $MD5 git openssl; do
    type -t $ii &>/dev/null || msg_quit "Missing dependency: $ii"
done

function fn_git () { cd $DATA_DIR && git $* && cd - ; }

function fn_check_latest_pull () {
    [ ! -f "$GIT_LATEST_PULL" ] && echo "0" > $GIT_LATEST_PULL
    local secs_latest_pull=$(( $(date +"%s") - $(cat $GIT_LATEST_PULL) ))
    [ "$secs_latest_pull" -gt "$GIT_PULL_INTERVAL" ] \
    && fn_git pull \
    && echo $(date +"%s") > $GIT_LATEST_PULL
}

if [ -f "$CONFIG_FILE" ]; then
    DATA_DIR=$(get_param 'data_dir' $CONFIG_FILE)
    GIT_REPO=$(get_param 'git_repo' $CONFIG_FILE)
    GIT_PULL_INTERVAL=$(( $(get_param 'pull_hours_interval' $CONFIG_FILE) * 3600 ))
    
    if [ "$GIT_REPO" = "$DEFAULT_GIT_URL_MSG" ]; then
        msg_quit "Please specify your git_repo from $CONFIG_FILE"
    elif [ -d "$DATA_DIR" ] && cd $DATA_DIR && git status &>/dev/null && cd - &>/dev/null; then
        fn_check_latest_pull
    else
        mkdir -p $DATA_DIR &>/dev/null
        [ "$(ls -A $DATA_DIR)" ] && msg_quit "$DATA_DIR is not empty, cant proceed."
        echo "Cloning $GIT_REPO to $DATA_DIR"
        cd $DATA_DIR \
        && git clone $GIT_REPO $DATA_DIR \
        && cd - &>/dev/null \
        && echo "done." 
        echo $(date +"%s") > $GIT_LATEST_PULL 
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

NOTES_DIR=$DATA_DIR/notes ; mkdir -p $NOTES_DIR 2>/dev/null
TAGS_DIR=$DATA_DIR/tags   ; mkdir -p $DATA_DIR 2>/dev/null
UNIQUE_TAGS_FILE=$DATA_DIR/unique_tags
INDEX_TRUC_FILE=$DATA_DIR/index_truncate
DEFAULT_MODE="0600"

function ff_topic    () { echo $(fmt_font bold  color white   "$1"); }
function ff_index    () { echo $(fmt_font color light_yellow  "$1"); }
function ff_content  () { echo $(fmt_font color dark_gray     "$1"); }
function ff_tags     () { echo $(fmt_font color cyan          "$1"); }
function ff_sel_tags () { echo $(fmt_font color light_cyan    "$1"); }

function fn_preview_file () { 
    file_in=$1
    [ -f "$file_in" ] || msg_quit "File not found: $file_in"

    if [ "$(head -c 6 $file_in)" = "Salted" ]; then
        echo -e $(ff_content "Encrypted")
    else
        echo -e $(ff_content "$(head -c $TERM_COLS $file_in 2>/dev/null)")
    fi
}

function update_unique_tags () {
    cat $TAGS_DIR/* \
    | tr ' ' '\n' \
    | sort \
    | uniq > $UNIQUE_TAGS_FILE
}

function fn_encrypt_file () {
    local note=$1
    echo -n "Enter password: "
    openssl enc -aes-256-cbc -md sha512 -pbkdf2 -iter 80 -salt -in $note -out $note.$CMD_TIME -pass pass:$(read -s && echo $REPLY) \
    && mv $note.$CMD_TIME $note
}

function fn_decrypt_file () {
    local note=$1
    [ "$(head -c 6 $note)" = "Salted" ] \
    && echo -n "Enter password: " \
    && openssl enc -aes-256-cbc -md sha512 -pbkdf2 -iter 80 -salt -d -in $note -out $note.$CMD_TIME -pass pass:$(read -s && echo $REPLY)
}

function update_index_truncate () {
    local len=1
    while [ $((for ii in $(ls -1 $NOTES_DIR); do echo ${ii::$len}; done) | sort | uniq -d | wc -l) -gt 0 ]; do
        len=$(( len + 1 ))
    done
    echo $len > $INDEX_TRUC_FILE
}

function commit_push () { 
    local ftz=$(date +"%F %T %Z")
    local commit_msg_file=/tmp/commit_msg_file.$CMD_TIME

    if [ "$(fn_git status --porcelain=v1 2>/dev/null | wc -l)" -gt 0 ]; then
        echo "$ftz - $CMD_NAME backup." > $commit_msg_file 
        fn_git commit -a -F $commit_msg_file 
        fn_git push 
        rm $commit_msg_file 
    fi
}

function force_pull () {
    echo "0" > $GIT_LATEST_PULL && fn_check_latest_pull
}

USAGE="$(ff_topic NAME)\n\
    ${CMD_NAME} - A note-keeping script written in bash.\n\
\n$(ff_topic SYNTAX)\n\
    $CMD_NAME {new|grep|list|edit|rm}
" 
function print_usage () { echo -e "$USAGE"; }

function set_param () {
    local  param=$1 ; shift
    local   file=$1 ; shift
    local values="$*"
    fn_file_exists $file

    if grep -q $param $file; then
        sed -i .tmp "s/^${param} .*/${param} ${values}/g" $file 
        rm ${file}.tmp
    else
        echo "$param $values" >> $file
    fi
}

function new_note () {
    local id=$1
    grep -q '^:pass.*' <<<$id && local password=T && shift && id=$1
    [ -f "$id" ] && local import_file=$id && shift
    local new_tags="$*"

    while [ -z "$new_tags" ]; do read -p "Tags: " new_tags; done

    local tmp_file_path=$NOTES_DIR/tmp.$CMD_TIME
    
    [ -n "$import_file" ] && install -m $DEFAULT_MODE $import_file $tmp_file_path 

    vim $tmp_file_path \
    && local new_md5=$($MD5 $tmp_file_path | awk '{print $1}') \
    && local new_file_path=$NOTES_DIR/$new_md5 \
    && mv $tmp_file_path $new_file_path \
    && echo "Saving note $(ff_index $new_md5): $(ff_tags $new_tags)" \
    && echo "$new_tags" > $TAGS_DIR/$new_md5 \
    && update_unique_tags \
    && update_index_truncate 
    
    [ -n "$password" ] && fn_encrypt_file $new_file_path

    fn_git add $new_file_path 
    commit_push
}

function grep_note () {
    [ -z "$1" ] && return 0
    local whole_query="$*"
    local pattern="${whole_query// /\\|}"
    local files_list="$(find $NOTES_DIR -type f)"
    local index_trunc=$(cat $INDEX_TRUC_FILE)

    for ii in $whole_query; do
        [ -z "$files_list" ] && return
        local files_list="$(grep $ii -l $files_list)" 
    done

    for ii in $files_list; do
        local id=$(basename $ii)
        echo -e $(ff_index ${id::$index_trunc})": "$(ff_tags "$(cat $TAGS_DIR/$id)")
        grep -h --color=auto $pattern $ii
        echo ""
    done
}

function grep_by_tags () {
    [ -z "$1" ] && echo -e $(ff_tags "$(cat $UNIQUE_TAGS_FILE | paste -s -)") && return 0
    local whole_query="$*"
    local pattern="${whole_query// /\\|}"
    local files_list="$(find $TAGS_DIR -type f)"

    for ii in $whole_query; do
        [ -z "$files_list" ] && return
        local files_list="$(grep $ii -l $files_list)" 
    done

    for ii in $files_list; do
        local index=$(basename $ii)
        local remaining_tags=$(cat $ii | sed "s/$pattern//g")
        echo -e $(ff_index $index)":"$(ff_sel_tags "$whole_query")" "$(ff_tags "$remaining_tags")
        fn_preview_file $ii
        echo ""
    done
}

function list_notes () {
    local wc_tags_dir=$(ls -1 $TAGS_DIR | wc -l)
    [ "$wc_tags_dir" = "0" ] && msg_quit "$TAGS_DIR is empty."
    local index_trunc=$(cat $INDEX_TRUC_FILE)

    for ii in $(ls -1 $NOTES_DIR); do
        id_trunc=${ii::$index_trunc}
        local tags=$(cat $TAGS_DIR/$ii)
        echo "$(ff_index $id_trunc): "$(ff_tags "$tags")
        fn_preview_file $NOTES_DIR/$ii
    done
    echo ""
}

function edit_note () {
    local id=$1
    grep -q '^:pass.*' <<<$id && local password=T && shift && id=$1

    local note_file_path=$(ls -1 $NOTES_DIR/${id}*)
    local tags_file_path=$(ls -1 $TAGS_DIR/${id}*)
    local note_old_md5=$(basename $note_file_path)

    if [ -f "$note_file_path" ]; then
        [ -f "$tags_file_path" ] && [ -s "$tags_file_path" ] || msg_quit "Tags not found for $id"
        local old_tags=$(cat $tags_file_path)
        local new_tags=""
        
        if [ "$BASH_V" -gt "3" ]; then
            while [ -z "$new_tags" ]; do read -e -i "$old_tags" -p "Tags: " new_tags; done
        else
            echo -e "Current tags: "$(ff_tags "$old_tags")
            read -p "Type new tags or [ENTER] to keep the current: " new_tags
            [ -z "$new_tags" ] && new_tags="$old_tags"
        fi

        if [ ! "$new_tags" = "$old_tags" ]; then
            echo "$new_tags" > $tags_file_path
            update_unique_tags
        fi

        vim $note_file_path \
        && local new_md5=$($MD5 $note_file_path | awk '{print $1}') \
        && mv $note_file_path $NOTES_DIR/$new_md5 2>/dev/null \
        && note_file_path=$NOTES_DIR/$new_md5 \
        && mv $TAGS_DIR/$note_old_md5 $TAGS_DIR/$new_md5 \
        && update_index_truncate 
        
        [ -n "$password" ] && fn_encrypt_file $note_file_path
        commit_push
    else
        msg_quit "Note $(ff_index $id) not found."
    fi
}

function cat_note () {
    local id=$1
    [ -z "$id" ] && msg_quit "USAGE: $CMD_NAME show <ID>"
    local note=$(ls -1 $NOTES_DIR/$id*)
    [ ! -f "$note" ] && msg_quit "File not found: $note"
    fn_decrypt_file $note
    cat $note
    [ -f $note.$CMD_TIME ] && mv $note.$CMD_TIME $note
}

function rm_note () {
    local id=$1
    [ -z "$id" ] && echo "id is empty" && list_notes && return
    rm $NOTES_DIR/$id $TAGS_DIR/$id 2>/dev/null \
    && update_unique_tags \
    && update_index_truncate \
    && commit_push \
    list_notes
}

function fn_install () {
    local complete_src=${CMD_NAME}.src
    [ -d ~/init_source ] && ln -s $(pwd -P $0)"/$complete_src" ~/init_source/$complete_src 2>/dev/null
    [ -d ~/bin ]         && ln -s $CMD_REAL_PATH ~/bin/$CMD_BASENAME 2>/dev/null
}

function comptag () {
    [ -z "$1" ] && cat $UNIQUE_TAGS_FILE | paste -s - && return
    local intersect="$*"
    local pattern=$(sed 's/\(\w*\)/\\<\1\\>/g' <<<$intersect | sed 's/ /\\|/g')
    grep -v $pattern $UNIQUE_TAGS_FILE | paste -s -
}

case $1 in
    *help)   print_usage              ;;
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
#15
