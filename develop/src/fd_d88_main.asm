;-----------------------------------;
;	X1turbo FD → D88イメージファイル化ツール
; 動作: LSX-Dodgers / X1turbo専用
; 機種判定と開始確認を経てFDをD88へ保存し、情報表示モードも選択する。
;-----------------------------------;
; (c)2026 X1turboAgency
; SPDX-License-Identifier: MIT

	ORG		0100h
	jp		START
;
; FD→D88のメイン。書き戻し用のコードはリンクしない。
;-----------------------------------;
; FDの保存・情報表示を実行する。
; 入力条件: LSX-Dodgersのコマンドテール。
; 戻り値: 処理後は0000hへ移行する。通常のサブルーチンとしては戻らない。
;-----------------------------------;
START:
	call	cli_parse
	jp		c, dump_cli_error
;
	ld		a, (cli_help)
	or		a
	jp		nz, cli_exit_help
;
	call	check_supported_platform
	jp		c, 0000h
;
	call	print_title_str
	ld		a, (cli_info)
	or		a
	jp		nz, dump_info_confirm
;
	call	d88_prepare_name
	jp		c, dump_name_error
;
	call	confirm_dump
	jp		c, 0000h
;
	call	print_read_filename
	call	print_settings
	call	init_fdd_system
	call	read_report_init
	call	d88_create
	jp		c, dump_error
;
;-----------------------------------;
; 現在トラックを取得し、エラーを記録してD88へ保存する。
;-----------------------------------;
track_loop:
	call	COMMAND_READ_DISK
	jr		c, dump_capture_failed
;
	ld		a, (sector_num)
	call	read_report_record_sectors
	call	d88_write_track
	jr		c, dump_error
;
dump_next_track:
	call	next_track
	jr		nc, track_loop
;
	call	d88_finish
	jr		c, dump_error
;
	ld		a, (d88_read_errors)
	or		a
	jr		nz, dump_read_errors
;
	call	print_done
	jp		0000h
;
dump_read_errors:
	ld		de, d88_msg_read_errors
	call	print_system
	call	read_report_print
	jp		0000h
;
;-----------------------------------;
; トラック取得の失敗を記録し、継続可能かを判定する。
;-----------------------------------;
dump_capture_failed:
	push	af
	; 媒体エラーは未収録として次へ進む。未準備/タイムアウトは中断する。
	call	read_report_record_track

	ld		a, (capture_sectors_read)
	call	read_report_record_sectors
	pop		af

	call	fdd_check_abort
	jr		c, dump_access_error
;
	jr		dump_next_track
;
dump_access_error:
	call	fdd_abort_command

	ld		hl, fdd_msg_access
	ld		(d88_error_message), hl
dump_error:
	call	motor_off
	call	d88_abort
	call	d88_print_error
	call	read_report_print
	jp		0000h
;
dump_name_error:
	call	d88_print_error
	jp		0000h
;
dump_info_confirm:
	call	confirm_info
	jp		c, 0000h
;
	jp		disk_info_mode
;
dump_cli_error:
	jp		cli_exit_error
;
END
