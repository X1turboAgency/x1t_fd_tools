;-----------------------------------;
; コマンドテールを解析する。FCB1はオプションの位置に依存させない。
; 位置引数: fdN-2d / fdN-2dd / fdN-2hd（N=0～3）、ファイル名
; -tr 開始-終了/単一、-h、-i（FD2IMGのみ。ファイル名は指定しない）
; 戻り値: CF=1 エラー。cli_help=1 使用方法のみ表示。
; cli_usage_only=1: 引数不足のため使用方法だけを表示して終了する。
; ファイル名はFCB1に展開。ドライブ省略は0を維持する。
; FD・メディア・ファイル名とオプションを検証し、実行パラメータを設定する。
;-----------------------------------;
; (c)2026 X1turboAgency
; SPDX-License-Identifier: MIT
;-----------------------------------;
; コマンドテールを解析し、FD・メディア・範囲とFCBを設定する。
; 入力条件: 0080hのコマンドテール。
; 戻り値: Cy=0: 解析成功。Cy=1: 引数不足または不正指定。
;-----------------------------------;
cli_parse:
	xor		a
	ld		(cli_help), a
	ld		(cli_usage_only), a
IF TOOL_RESTORE
ELSE
	ld		(cli_info), a
ENDIF
	ld		(cli_fd_seen), a
	ld		(cli_tr_seen), a
	ld		(cli_file_seen), a
	ld		(drive_no), a
	ld		(start_track_no), a
	ld		hl, cli_msg_option
	ld		(cli_error), hl
	; BDOSのDTAと重なるため、解析前にテールを退避する。
	ld		a, (0080h)
	cp		128
	jp		nc, cli_bad
;
	ld		c, a
	ld		b, 0
	ld		hl, 0081h
	ld		de, cli_line
	or		a
	jr		z, cli_copy_done
;
	ldir
cli_copy_done:
	xor		a
	ld		(de), a
	ld		hl, FCB1
	ld		b, 37
cli_clear_fcb:
	ld		(hl), a
	inc		hl
	djnz	cli_clear_fcb
;
	ld		hl, FCB1+1
	ld		b, 11
cli_blank_name:
	ld		(hl), ' '
	inc		hl
	djnz	cli_blank_name
;
	ld		hl, cli_line
	ld		(cli_cursor), hl

;-----------------------------------;
; 次の引数を取得し、オプションと位置引数に振り分ける。
;-----------------------------------;
cli_loop:
	call	cli_token
	jp		c, cli_bad
;
	ld		a, (cli_token_buf)
	or		a
	jp		z, cli_finish
;
	cp		'-'
	jp		nz, cli_positional
;
	ld		hl, cli_token_buf
	ld		de, cli_opt_tr
	call	cli_equal
	jp		z, cli_tracks
;
IF TOOL_RESTORE
ELSE
	ld		de, cli_opt_info
	call	cli_equal
	jp		z, cli_set_info
;
ENDIF
	ld		de, cli_opt_help
	call	cli_equal
	jr		z, cli_set_help
;
	jp		cli_bad
;
IF TOOL_RESTORE
ELSE
cli_set_info:
	ld		a, (cli_info)
	or		a
	jp		nz, cli_duplicate
;
	inc		a
	ld		(cli_info), a
	jp		cli_loop
;
ENDIF
cli_set_help:
	ld		a, 1
	ld		(cli_help), a
	jp		cli_loop
;
cli_tracks:
	ld		a, (cli_tr_seen)
	or		a
	jp		nz, cli_duplicate
;
	inc		a
	ld		(cli_tr_seen), a
	call	cli_token
	jp		c, cli_bad_track
;
	ld		a, (cli_token_buf)
	or		a
	jp		z, cli_missing_track
;
	ld		hl, cli_token_buf
	call	cli_decimal
	jp		c, cli_bad_track
;
	ld		(start_track_no), a
	ld		(end_track_no), a
	ld		a, (hl)
	or		a
	jp		z, cli_loop
;
	cp		'-'
	jp		nz, cli_bad_track
;
	inc		hl
	call	cli_decimal
	jp		c, cli_bad_track
;
	ld		(end_track_no), a
	ld		a, (hl)
	or		a
	jp		nz, cli_bad_track
;
	jp		cli_loop

;-----------------------------------;
; 最初の位置引数は物理FDDとメディアの組。その次だけをファイル名とする。
;-----------------------------------;
cli_positional:
	ld		a, (cli_fd_seen)
	or		a
	jr		z, cli_drive_argument
;
	call	cli_get_target
	jp		nc, cli_duplicate_fd
;
	jp		cli_filename
;
cli_drive_argument:
	call	cli_get_target
	jp		c, cli_bad_fd
;
	ld		(drive_no), a
	ld		a, b
	ld		(media_type), a
	ld		a, c
	ld		(cli_max_track), a
	ld		a, 1
	ld		(cli_fd_seen), a
	jp		cli_loop

;-----------------------------------;
; 完全一致するFD[0～3]-2D/2DD/2HDだけを受け付ける。
; CF=0: Areg=ドライブ、Breg=メディア、Creg=最終トラック。CF=1: 不一致。
;-----------------------------------;
; FD番号とメディアを組にした位置引数を識別する。
; 入力条件: cli_token_buf: 大文字化済みのトークン。
; 戻り値: Cy=0: Areg=FD番号、Breg=メディア、Creg=最終トラック。Cy=1: 不一致。
;-----------------------------------;
cli_get_target:
	ld		a, (cli_token_buf)
	cp		'F'
	jr		nz, cli_not_fd
;
	ld		a, (cli_token_buf+1)
	cp		'D'
	jr		nz, cli_not_fd
;
	ld		a, (cli_token_buf+3)
	cp		'-'
	jr		nz, cli_not_fd
;
	ld		a, (cli_token_buf+2)
	sub		'0'
	cp		4
	jr		nc, cli_not_fd
;
	push	af
	ld		hl, cli_token_buf+4
	ld		de, cli_media_2d
	call	cli_equal
	jr		z, cli_target_2d
;
	ld		de, cli_media_2dd
	call	cli_equal
	jr		z, cli_target_2dd
;
	ld		de, cli_media_2hd
	call	cli_equal
	jr		z, cli_target_2hd
;
	pop		af
cli_not_fd:
	scf
	ret
;
cli_target_2d:
	ld		b, DISK_TYPE_2D
	ld		c, 79
	jr		cli_target_ok
;
cli_target_2dd:
	ld		b, DISK_TYPE_2DD
	ld		c, 159
	jr		cli_target_ok
;
cli_target_2hd:
	ld		b, DISK_TYPE_2HD
	ld		c, 153
cli_target_ok:
	pop		af
	or		a
	ret
;
cli_filename:
	ld		a, (cli_file_seen)
	or		a
	jp		nz, cli_bad_name
;
	inc		a
	ld		(cli_file_seen), a
	ld		hl, cli_token_buf
	ld		a, (hl)
	ld		b, a
	inc		hl
	ld		a, (hl)
	cp		':'
	jr		nz, cli_name_start
;
	ld		a, b
	sub		'A'-1
	cp		1
	jp		c, cli_bad_name
;
	cp		27
	jp		nc, cli_bad_name
;
	ld		(FCB1), a
	inc		hl
	jr		cli_name_body
;
cli_name_start:
	dec		hl
cli_name_body:
	ld		de, FCB1+1
	ld		b, 8
	xor		a
	ld		(cli_name_count), a
cli_name_loop:
	ld		a, (hl)
	or		a
	jr		z, cli_name_done
;
	cp		'.'
	jr		z, cli_extension
;
	call	cli_name_char
	jp		c, cli_bad_name
;
	ld		a, b
	or		a
	jp		z, cli_bad_name
;
	ld		a, (hl)
	ld		(de), a
	inc		de
	inc		hl
	dec		b
	ld		a, (cli_name_count)
	inc		a
	ld		(cli_name_count), a
	jr		cli_name_loop
;
cli_extension:
	ld		a, (cli_name_count)
	or		a
	jp		z, cli_bad_name
;
	inc		hl
	ld		de, FCB1+9
	ld		b, 3
cli_ext_loop:
	ld		a, (hl)
	or		a
	jp		z, cli_loop
;
	call	cli_name_char
	jp		c, cli_bad_name
;
	ld		a, b
	or		a
	jp		z, cli_bad_name
;
	ld		a, (hl)
	ld		(de), a
	inc		de
	inc		hl
	dec		b
	jr		cli_ext_loop
;
cli_name_done:
	ld		a, (cli_name_count)
	or		a
	jp		z, cli_bad_name
;
	jp		cli_loop
;
;-----------------------------------;
; 必須引数とモード別のファイル名条件を最終検査する。
;-----------------------------------;
cli_finish:
	ld		a, (cli_help)
	or		a
	ret		nz
;
	ld		a, (cli_fd_seen)
	or		a
	jp		z, cli_missing_fd
;
	call	cli_validate_range
	ret		c
;
IF TOOL_RESTORE
	ld		a, (cli_file_seen)
	or		a
	jp		z, cli_missing_filename
;
ELSE
	ld		a, (cli_info)
	or		a
	jr		z, cli_dump_filename_required
;
	ld		a, (cli_file_seen)
	or		a
	jp		nz, cli_info_filename_error
;
	jr		cli_info_name_ok
;
cli_dump_filename_required:
	ld		a, (cli_file_seen)
	or		a
	jp		z, cli_missing_filename
;
cli_info_name_ok:
ENDIF
	jp		cli_ok
;
; 範囲はメディアごとの上限で、ファイル名不足の判定より先に検証する。
;-----------------------------------;
; 省略時の終了番号を設定し、メディアのトラック上限を検査する。
; 入力条件: start_track_no、end_track_no、cli_tr_seen、cli_max_track。
; 戻り値: Cy=0: 有効。Cy=1: 範囲外または開始番号が終了番号を超える。
;-----------------------------------;
cli_validate_range:
	ld		a, (cli_tr_seen)
	or		a
	jr		nz, cli_check_range
;
	ld		a, (cli_max_track)
	ld		(end_track_no), a
cli_check_range:
	ld		a, (end_track_no)
	ld		b, a
	ld		a, (cli_max_track)
	cp		b
	jp		c, cli_bad_track
;
	ld		a, (start_track_no)
	cp		b
	jp		c, cli_ok
;
	jp		nz, cli_bad_track
;
cli_ok:
	xor		a
	ret
;
; 次の空白区切りトークンを大文字化して取得。最大31バイト。
;-----------------------------------;
; 空白を読み飛ばし、次のトークンを大文字化して取り出す。
; 入力条件: cli_cursor: 読取り位置。
; 戻り値: Cy=0: cli_token_bufに0終端文字列。Cy=1: 31文字を超過。
;-----------------------------------;
cli_token:
	ld		hl, (cli_cursor)
cli_skip_space:
	ld		a, (hl)
	cp		' '
	jr		z, cli_skip_one
;
	cp		9
	jr		nz, cli_token_start
;
cli_skip_one:
	inc		hl
	jr		cli_skip_space
;
cli_token_start:
	ld		de, cli_token_buf
	ld		b, 31
cli_token_loop:
	ld		a, (hl)
	or		a
	jr		z, cli_token_end
;
	cp		' '
	jr		z, cli_token_end
;
	cp		9
	jr		z, cli_token_end
;
	cp		'a'
	jr		c, cli_token_store
;
	cp		'z'+1
	jr		nc, cli_token_store
;
	sub		'a'-'A'
cli_token_store:
	ld		(de), a
	inc		hl
	inc		de
	djnz	cli_token_loop
;
	scf
	ret
;
cli_token_end:
	xor		a
	ld		(de), a
	ld		(cli_cursor), hl
	ret
;
; HLとDEの0終端文字列。HLregは保存。Z=一致。
;-----------------------------------;
; 0終端文字列同士を比較する。
; 入力条件: HLreg、DEreg: 比較する文字列の先頭。
; 戻り値: Z: 一致。NZ: 不一致。HLregは保存する。
;-----------------------------------;
cli_equal:
	push	hl
cli_equal_loop:
	ld		a, (de)
	cp		(hl)
	jr		nz, cli_equal_end
;
	inc		de
	inc		hl
	or		a
	jr		nz, cli_equal_loop
;
cli_equal_end:
	pop		hl
	ret
;
; HLregの10進数をAへ。0..255のみ許可。HLregは区切り文字を指す。
;-----------------------------------;
; 10進文字列を0～255の整数へ変換する。
; 入力条件: HLreg: 数値文字列の先頭。
; 戻り値: Cy=0: Areg=数値、HLreg=区切り位置。Cy=1: 数値不正または桁あふれ。
;-----------------------------------;
cli_decimal:
	ld		a, (hl)
	cp		'0'
	ret		c
;
	cp		'9'+1
	ccf
	ret		c
;
	ld		c, 0
cli_decimal_loop:
	ld		a, (hl)
	sub		'0'
	cp		10
	jr		nc, cli_decimal_done
;
	ld		b, a
	ld		a, c
	cp		26
	jr		nc, cli_decimal_bad
;
	add		a, a
	ld		d, a
	add		a, a
	add		a, a
	add		a, d
	add		a, b
	jr		c, cli_decimal_bad
;
	ld		c, a
	inc		hl
	jr		cli_decimal_loop
;
cli_decimal_done:
	ld		a, c
	or		a
	ret
;
cli_decimal_bad:
	scf
	ret
;
; パス・ワイルドカード・FCB制御文字は受け付けない。
;-----------------------------------;
; ファイル名に使用できるASCII文字かを検査する。
; 入力条件: Areg: 検査対象の文字。
; 戻り値: Cy=0: 使用可能。Cy=1: 制御文字・禁止文字。
;-----------------------------------;
cli_name_char:
	cp		'!'
	ret		c
;
	cp		07fh
	ccf
	ret		c
;
	push	hl
	ld		hl, cli_forbidden
cli_char_check:
	cp		(hl)
	jr		z, cli_char_bad
;
	inc		hl
	push	af
	ld		a, (hl)
	or		a
	jr		z, cli_char_ok
;
	pop		af
	jr		cli_char_check
;
cli_char_ok:
	pop		af
	pop		hl
	or		a
	ret
;
cli_char_bad:
	pop		hl
	scf
	ret
;
cli_duplicate:
	ld		hl, cli_msg_duplicate
	jr		cli_set_error
;
cli_bad_fd:
	ld		hl, cli_msg_fd
	jr		cli_set_error
;
cli_duplicate_fd:
	ld		hl, cli_msg_fd_duplicate
	jr		cli_set_error
;
; 引数不足は通常の不正指定と区別し、使用方法だけを表示する。
cli_missing_fd:
	ld		hl, cli_msg_fd
	jr		cli_need_usage
;
cli_missing_filename:
	ld		hl, cli_msg_file_required
	jr		cli_need_usage
;
cli_missing_track:
	ld		hl, cli_msg_track
cli_need_usage:
	ld		a, 1
	ld		(cli_usage_only), a
	jr		cli_set_error
;
cli_bad_track:
	ld		hl, cli_msg_track
	jr		cli_set_error
;
cli_bad_name:
	ld		hl, cli_msg_name
	jr		cli_set_error
;
IF TOOL_RESTORE
ELSE
cli_info_filename_error:
	ld		hl, cli_msg_info_name
	jr		cli_set_error
;
ENDIF
cli_bad:
	ld		hl, cli_msg_option
cli_set_error:
	ld		(cli_error), hl
	scf
	ret
;
; 必須引数不足は使用方法のみ。それ以外の不正指定は理由も表示する。
;-----------------------------------;
; 引数エラーを必要に応じて表示し、使用方法を表示して終了する。
; 入力条件: cli_usage_only、cli_error。
; 戻り値: 呼出し元には戻らず、0000hへ移行する。
;-----------------------------------;
cli_exit_error:
	ld		a, (cli_usage_only)
	or		a
	call	z, cli_print_error
;-----------------------------------;
; 使用方法を表示してコマンドを終了する。
; 入力条件: なし。
; 戻り値: 呼出し元には戻らず、0000hへ移行する。
;-----------------------------------;
cli_exit_help:
	call	cli_print_help
	jp		0000h
;
;-----------------------------------;
; 解析時に設定したエラーメッセージを表示する。
; 入力条件: cli_error: メッセージのアドレス。
; 戻り値: 表示のみ。フラグは判定に使用しない。
;-----------------------------------;
cli_print_error:
	ld		de, (cli_error)
	jp		print_system
;
;-----------------------------------;
; 使用方法とオプションの説明を表示する。
; 入力条件: なし。
; 戻り値: 表示のみ。フラグは判定に使用しない。
;-----------------------------------;
cli_print_help:
	ld		de, cli_usage
	jp		print_system
;
cli_usage:
IF TOOL_RESTORE
	db		"Usage: IMG2FD fdN-media input.d88 [-tr start-end]", 13, 10
ELSE
	db		"Usage: FD2IMG fdN-media output.d88 [-tr start-end]", 13, 10
	db		"       FD2IMG fdN-media -i [-tr start-end]", 13, 10
ENDIF
	db		" fdN-media is required (N=0-3; media=2d/2dd/2hd).", 13, 10
	db		" Example: fd0-2d. Specify FD first, then filename.", 13, 10
	db		" -tr default: 2D=0-79 / 2DD=0-159 / 2HD=0-153. Single track OK.", 13, 10
IF TOOL_RESTORE
ELSE
	db		" -i: Show IDs as #hex/bytes in disk order, then format summary.", 13, 10
ENDIF
	db		" -h: Show help. Options may appear anywhere.", 13, 10, "$"
cli_msg_fd: db "Error: First argument must be fdN-2d/2dd/2hd (N=0-3).",13,10,"$"
cli_msg_fd_duplicate: db "Error: Specify one FD as the first argument.",13,10,"$"
cli_msg_file_required:
IF TOOL_RESTORE
	db		"Error: Specify input D88 filename after FD.",13,10,"$"
ELSE
	db		"Error: Specify output D88 filename after FD.",13,10,"$"
ENDIF
cli_msg_option: db "Error: Unknown option or argument too long.",13,10,"$"
cli_msg_duplicate: db "Error: Duplicate option.",13,10,"$"
cli_msg_track: db "Error: Track must be within media limits; use number or start-end.",13,10,"$"
cli_msg_name: db "Error: Use an 8.3 filename: [drive:]name.ext.",13,10,"$"
IF TOOL_RESTORE
ELSE
cli_msg_info_name: db "Error: Do not specify an output filename with -i.",13,10,"$"
cli_opt_info: db "-I",0
cli_info: db 0
ENDIF
cli_media_2d: db "2D",0
cli_media_2dd: db "2DD",0
cli_media_2hd: db "2HD",0
cli_opt_tr: db "-TR",0
cli_opt_help: db "-H",0
cli_forbidden: db 05ch,"/:;,.?*+=<>|",34,0
cli_help: db 0
cli_usage_only: db 0
cli_fd_seen: db 0
cli_tr_seen: db 0
cli_file_seen: db 0
cli_name_count: db 0
cli_max_track: db 0
cli_error: dw cli_msg_option
cli_cursor: dw 0
cli_token_buf: ds 32,0
cli_line: ds 128,0
END
