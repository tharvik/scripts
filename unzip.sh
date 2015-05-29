#!/bin/sh

set -eu

readonly FILE="${1}"

next() {
	local size=${1}

	local width=$((size > 4 * 4 ? 4 * 4 : size))
	width=$((width + 1))

	local res=''
	local lines="$(head -c ${size} | xxd -g 1 | cut -d ' ' -f 2-${width})"

	for line in ${lines}
	do
		res=${line}${res}
	done

	echo ${res}
}

next_str() {
	local size=${1}

	head -c ${size}
}

to_int() {
	local value="${1}"

	printf "%d\n" "0x${value}"
}

parse_file_header() {
	file_version="$(to_int $(next 2))"
	file_flag="$(next 2)"
	file_compression="$(next 2)"
	file_mod_time="$(next 2)"
	file_mod_date="$(next 2)"
	file_crc="$(next 4)"
	file_size_comp="$(to_int $(next 4))"
	file_size_uncomp="$(to_int $(next 4))"
	file_name_length="$(to_int $(next 2))"
	file_extra_length="$(to_int $(next 2))"
	file_name="$(next_str ${file_name_length})"
	file_extra="$(next ${file_extra_length})"
}

parse_central_directory() {
	central_version_comp="$(to_int $(next 2))"
	central_version_uncomp="$(to_int $(next 2))"

	central_flag="$(next 2)"
	central_compression="$(next 2)"
	central_mod_time="$(next 2)"
	central_mod_date="$(next 2)"

	central_crc="$(next 4)"
	central_size_comp="$(to_int $(next 4))"
	central_size_uncomp="$(to_int $(next 4))"

	central_name_length="$(to_int $(next 2))"
	central_extra_length="$(to_int $(next 2))"
	central_comment_length="$(to_int $(next 2))"
	central_disk_begin="$(to_int $(next 2))"

	central_attr_internal="$(next 2)"
	central_attr_external="$(next 4)"

	central_offset="$(to_int $(next 4))"

	central_name="$(next_str ${central_name_length})"
	central_extra="$(next ${central_extra_length})"
	central_comment="$(next_str ${central_comment_length})"
}

parse_eocd() {
	eocd_disk_num=$(to_int $(next 2))
	eocd_disk_start=$(to_int $(next 2))
	eocd_num_cdr=$(to_int $(next 2))
	eocd_num_cdr_total=$(to_int $(next 2))

	eocd_size_cd=$(to_int $(next 4))
	eocd_offset=$(to_int $(next 4))

	eocd_comment_length=$(to_int $(next 2))
	[ ${eocd_comment_length} -eq 0 ] && return

	eocd_comment=$(to_int $(next ${eocd_comment_length}))
}

get_signature_type() {
	local signature="$(next 4)"
	case "${signature}" in
		'04034b50')
			echo file_header;;
		'08074b50')
			echo data_descriptor;;
		'02014b50')
			echo central_directory;;
		'06054b50')
			echo end_central_directory;;
		*)
			echo "unrecognized signature: ${signature}" 1>&2
			exit 1;;
	esac
}

skip() {
	local size=${1}

	head -c ${size} 1>/dev/null
}

skip_until() {

	local end_sign="${1}"

	while true
	do
		case $(get_signature_type) in
			'file_header')
				parse_file_header
				next ${file_size_comp} >/dev/null;;
			'data_descriptor')
				parse_data_descriptor;;
			'central_directory')
				parse_central_directory;;
			'end_central_directory')
				break;;
			*)
				echo 'return signature name unknow' 1>&1
				exit 1;;
		esac
	done
}

setup_eocd() {

	exec < "${FILE}"

	skip_until 'end_central_directory'

	parse_eocd
}

deflate() {
	:
}

# file header should already be parsed and the pointer next to data
extract() {
	head -c ${file_size_comp} - > "${file_name}"
}

exec < ${FILE}

signature="$(get_signature_type)"
while [ "${signature}" = 'file_header' ]
do
	parse_file_header
	extract

	signature="$(get_signature_type)"
done
