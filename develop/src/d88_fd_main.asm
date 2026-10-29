;-----------------------------------;
;	X1turbo D88イメージ → FD 書き戻しツール
; 動作: LSX-Dodgers
; X1turbo専用
; 機種判定と開始確認を経てD88を検査し、選択範囲をFDへ書き戻す。
;-----------------------------------;
; (c)2026 X1turboAgency
; SPDX-License-Identifier: MIT

	ORG		0100h
	jp		START
;
; D88→FDのメイン。選択トラックを全て検査してから書き込みを始める。
;-----------------------------------;
; D88の事前検査後にFDへの書き戻しを実行する。
; 入力条件: LSX-Dodgersのコマンドテール。
; 戻り値: 処理後は0000hへ移行する。通常のサブルーチンとしては戻らない。
;-----------------------------------;
START:
	call	cli_parse
	jp		c, restore_cli_error
;
	ld		a, (cli_help)
	or		a
	jp		nz, cli_exit_help
;
	call	check_supported_platform
	jp		c, 0000h
;
	call	print_title_str
	call	d88_prepare_name
	jp		c, restore_error
;
	call	confirm_restore
	jp		c, 0000h
;
	call	print_read_filename
	call	print_settings
	call	d88_input_open
	jp		c, restore_error
;
	call	d88_preflight
	jp		c, restore_error
;
	call	confirm_restore_start
	jr		c, restore_cancelled
;
	call	init_fdd_system
;-----------------------------------;
; 検査済み範囲を再読込みし、未収録トラックを除いてFDへ書く。
;-----------------------------------;
restore_loop:
	call	d88_load_track
	jr		c, restore_disk_error
;
	ld		a, (sector_num)
	or		a
	jr		z, restore_next
;
	call	fd_restore_track
	jr		c, restore_disk_error
;
restore_next:
	call	next_track
	jr		nc, restore_loop
;
	call	d88_input_close
	jr		c, restore_error
;
	call	print_done
	jp		0000h
;
restore_disk_error:
	call	motor_off
restore_error:
	call	d88_input_close_preserve
	call	d88_print_error
	jp		0000h
;
restore_cancelled:
	call	d88_input_close
	jp		c, restore_error
;
	jp		0000h
;
restore_cli_error:
	jp		cli_exit_error
;
END
