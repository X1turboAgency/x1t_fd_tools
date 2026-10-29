;-----------------------------------;
; FD読取りエラーをメモリへ保存し、指定範囲の処理終了後に一覧表示する。
; トラック毎に最大32件のRとFDC生ステータスを保存する。
; 4000h～6AEBhはFD2IMG専用ワーク。COMにゼロ領域を埋め込まない。
; FD読取り中のトラック・セクタエラーを記録し、処理終了後に一覧表示する。
;-----------------------------------;
; (c)2026 X1turboAgency
; SPDX-License-Identifier: MIT
READ_REPORT_SECTORS equ 32
READ_REPORT_BASE equ 04000h
READ_REPORT_COUNTS equ READ_REPORT_BASE+D88_TRACK_COUNT*READ_REPORT_SECTORS*2
READ_REPORT_PHASES equ READ_REPORT_COUNTS+D88_TRACK_COUNT
READ_REPORT_STATUS equ READ_REPORT_PHASES+D88_TRACK_COUNT
READ_REPORT_END equ READ_REPORT_STATUS+D88_TRACK_COUNT
READ_PHASE_SEEK equ 1
READ_PHASE_ID equ 2
READ_PHASE_BUFFER equ 3
READ_PHASE_OTHER equ 4
READ_PHASE_ID_OVER equ 5
READ_PHASE_INDEX equ 6

;-----------------------------------;
; エラー件数とトラック別の管理領域を初期化する。
; 入力条件: なし。
; 戻り値: 初期化のみ。フラグは判定に使用しない。
;-----------------------------------;
read_report_init:
	xor		a
	ld		(read_report_has_errors), a
	ld		(read_report_sector_total), a
	ld		(read_report_sector_total+1), a
	ld		(read_report_failed_tracks), a
	ld		hl, READ_REPORT_COUNTS
	ld		de, READ_REPORT_COUNTS+1
	ld		bc, READ_REPORT_END-READ_REPORT_COUNTS-1
	ld		(hl), a
	ldir
	ret
;
; Areg=取得済みセクタ数。CRC/RNF/Lost Data/Not Ready/Busyのみを記録。
; 削除データマークだけのセクタはエラーとして数えない。
;-----------------------------------;
; 取得済みセクタのFDC異常をトラック別に記録する。
; 入力条件: Areg: 取得済みセクタ数0～32。ID・状態バッファと現在トラック。
; 戻り値: セクタエラーを記録し集計を更新する。削除マーク単独は数えない。
;-----------------------------------;
read_report_record_sectors:
	or		a
	ret		z
;
	cp		READ_REPORT_SECTORS+1
	ret		nc
;
	ld		(read_report_sectors_left), a
	call	read_report_record_address
	ld		ix, read_id_list
	ld		iy, sector_status_buff
	xor		a
	ld		(read_report_found), a
read_report_record_sector:
	ld		a, (iy+SECTOR_STATUS_POS)
	and		09dh
	jr		z, read_report_record_next
;
	ld		a, (ix+ID_R_POS)
	ld		(hl), a
	inc		hl
	ld		a, (iy+SECTOR_STATUS_POS)
	ld		(hl), a
	inc		hl
	ld		a, (read_report_found)
	inc		a
	ld		(read_report_found), a
	push	hl
	ld		hl, (read_report_sector_total)
	inc		hl
	ld		(read_report_sector_total), hl
	pop		hl
	call	read_report_mark_error
read_report_record_next:
	ld		de, ID_SIZE
	add		ix, de
	inc		iy
	ld		a, (read_report_sectors_left)
	dec		a
	ld		(read_report_sectors_left), a
	jr		nz, read_report_record_sector
;
	ld		a, (start_track_no)
	ld		l, a
	ld		h, 0
	ld		de, READ_REPORT_COUNTS
	add		hl, de
	ld		a, (read_report_found)
	ld		(hl), a
	ret
;
; Areg=トラック取得を中断した状態値。取得段階はfd_captureから引き継ぐ。
;-----------------------------------;
; 取得失敗トラックの状態と失敗段階を記録する。
; 入力条件: Areg: 状態値。capture_error_phase、start_track_no。
; 戻り値: トラック別の失敗記録と件数を更新する。
;-----------------------------------;
read_report_record_track:
	ld		(read_report_status_work), a
	ld		a, (start_track_no)
	ld		l, a
	ld		h, 0
	ld		de, READ_REPORT_STATUS
	add		hl, de
	ld		a, (read_report_status_work)
	ld		(hl), a
	ld		a, (start_track_no)
	ld		l, a
	ld		h, 0
	ld		de, READ_REPORT_PHASES
	add		hl, de
	ld		a, (capture_error_phase)
	or		a
	jr		nz, read_report_phase_ready
;
	ld		a, READ_PHASE_OTHER
read_report_phase_ready:
	ld		(hl), a
	ld		a, (read_report_failed_tracks)
	inc		a
	ld		(read_report_failed_tracks), a
	jp		read_report_mark_error
;
;-----------------------------------;
; 読取りエラーがあることを共通ワークへ記録する。
; 入力条件: なし。
; 戻り値: read_report_has_errorsとd88_read_errorsを1にする。
;-----------------------------------;
read_report_mark_error:
	ld		a, 1
	ld		(read_report_has_errors), a
	ld		(d88_read_errors), a
	ret
;
; 現在の論理トラックの記録先。64バイト境界で計算する。
;-----------------------------------;
; 現在トラックのセクタエラー記録先を求める。
; 入力条件: start_track_no: 論理トラック番号。
; 戻り値: HLreg: 対象トラック用の64バイト領域。
;-----------------------------------;
read_report_record_address:
	ld		a, (start_track_no)
;-----------------------------------;
; 指定トラックのセクタエラー記録先を求める。
; 入力条件: Areg: 論理トラック番号。
; 戻り値: HLreg: READ_REPORT_BASE + トラック番号×64。
;-----------------------------------;
read_report_address_a:
	ld		l, a
	ld		h, 0
	add		hl, hl
	add		hl, hl
	add		hl, hl
	add		hl, hl
	add		hl, hl
	add		hl, hl
	ld		de, READ_REPORT_BASE
	add		hl, de
	ret
;
; エラーがない時は何も表示しない。異常終了時にも記録済み情報を表示できる。
;-----------------------------------;
; 記録した読取りエラーと合計件数を表示する。
; 入力条件: 初期化・記録済みのエラー管理領域。
; 戻り値: 表示のみ。エラーがない場合は表示しない。
;-----------------------------------;
read_report_print:
	ld		a, (read_report_has_errors)
	or		a
	ret		z
;
	ld		de, read_report_heading
	call	print_system
	xor		a
	ld		(read_report_track), a
	ld		(read_report_track_total), a
;-----------------------------------;
; トラックごとの失敗段階とセクタエラーを順に表示する。
;-----------------------------------;
read_report_print_track:
	ld		a, (read_report_track)
	ld		l, a
	ld		h, 0
	ld		de, READ_REPORT_COUNTS
	add		hl, de
	ld		a, (hl)
	ld		(read_report_sectors_left), a
	ld		b, a
	ld		de, D88_TRACK_COUNT
	add		hl, de
	ld		a, (hl)
	ld		(read_report_phase_work), a
	or		b
	jp		z, read_report_print_next
;
	ld		a, (read_report_track_total)
	inc		a
	ld		(read_report_track_total), a
	ld		a, (read_report_phase_work)
	or		a
	jr		z, read_report_print_sectors
;
	call	read_report_print_track_number
	ld		de, read_report_msg_track_fail
	ld		a, (cli_info)
	or		a
	jr		z, read_report_failure_label
;
	ld		de, read_report_msg_info_fail
read_report_failure_label:
	call	print_system
	ld		a, (read_report_phase_work)
	ld		de, read_report_msg_seek
	cp		READ_PHASE_SEEK
	jr		z, read_report_print_phase
;
	ld		de, read_report_msg_id
	cp		READ_PHASE_ID
	jr		z, read_report_print_phase
;
	ld		de, read_report_msg_buffer
	cp		READ_PHASE_BUFFER
	jr		z, read_report_print_phase
;
	ld		de, read_report_msg_id_over
	cp		READ_PHASE_ID_OVER
	jr		z, read_report_print_phase
;
	ld		de, read_report_msg_index
	cp		READ_PHASE_INDEX
	jr		z, read_report_print_phase
;
	ld		de, read_report_msg_other
read_report_print_phase:
	call	print_system
	ld		a, (read_report_track)
	ld		l, a
	ld		h, 0
	ld		de, READ_REPORT_STATUS
	add		hl, de
	ld		a, (hl)
	call	read_report_print_status
	; 独自の容量・INDEX等のエラーコードをFDCフラグとして解釈しない。
	ld		a, (read_report_phase_work)
	cp		READ_PHASE_BUFFER
	jr		nc, read_report_track_line_end
;
	call	read_report_print_flags
read_report_track_line_end:
	call	print_crlf
read_report_print_sectors:
	ld		a, (read_report_sectors_left)
	or		a
	jr		z, read_report_print_next
;
	ld		a, (read_report_track)
	call	read_report_address_a
	ld		(read_report_pointer), hl
read_report_print_sector:
	call	read_report_print_track_number
	ld		de, read_report_msg_sector
	call	print_system
	ld		hl, (read_report_pointer)
	ld		a, (hl)
	call	print_decimal
	ld		hl, (read_report_pointer)
	inc		hl
	ld		a, (hl)
	inc		hl
	ld		(read_report_pointer), hl
	call	read_report_print_status
	call	read_report_print_flags
	call	print_crlf
	ld		a, (read_report_sectors_left)
	dec		a
	ld		(read_report_sectors_left), a
	jr		nz, read_report_print_sector
;
read_report_print_next:
	ld		a, (read_report_track)
	inc		a
	ld		(read_report_track), a
	cp		D88_TRACK_COUNT
	jp		c, read_report_print_track
;
	ld		de, read_report_msg_total_tracks
	call	print_system
	ld		a, (read_report_track_total)
	call	print_decimal
	ld		a, (cli_info)
	or		a
	jr		nz, read_report_track_failure_total
;
	ld		de, read_report_msg_total_sectors
	call	print_system
	ld		hl, (read_report_sector_total)
	call	read_report_print_word
read_report_track_failure_total:
	ld		de, read_report_msg_failed_tracks
	ld		a, (cli_info)
	or		a
	jr		z, read_report_failure_total_label
;
	ld		de, read_report_msg_info_total
read_report_failure_total_label:
	call	print_system
	ld		a, (read_report_failed_tracks)
	call	print_decimal
	jp		print_crlf
;
;-----------------------------------;
; エラー一覧のトラック番号を表示する。
; 入力条件: read_report_track: 表示対象。
; 戻り値: 表示のみ。フラグは判定に使用しない。
;-----------------------------------;
read_report_print_track_number:
	ld		de, read_report_msg_track
	call	print_system
	ld		a, (read_report_track)
	jp		print_decimal
;
;-----------------------------------;
; 状態値を2桁16進数で表示し、原因表示用に保持する。
; 入力条件: Areg: 状態値。
; 戻り値: read_report_status_workを更新する。フラグは判定に使用しない。
;-----------------------------------;
read_report_print_status:
	ld		(read_report_status_work), a
	ld		hl, read_report_status_hex
	call	hex2_asc
	ld		de, read_report_msg_status
	jp		print_system
;
; 複数の原因ビットが立っている時はすべて表示する。
;-----------------------------------;
; 状態値に含まれるエラー原因をすべて表示する。
; 入力条件: read_report_status_work: FDC状態値。
; 戻り値: 表示のみ。独自エラーコードには呼び出さない。
;-----------------------------------;
read_report_print_flags:
	ld		a, (read_report_status_work)
	bit		7, a
	ld		de, read_report_flag_ready
	call	nz, print_system
	ld		a, (read_report_status_work)
	bit		4, a
	ld		de, read_report_flag_rnf
	call	nz, print_system
	ld		a, (read_report_status_work)
	bit		3, a
	ld		de, read_report_flag_crc
	call	nz, print_system
	ld		a, (read_report_status_work)
	bit		2, a
	ld		de, read_report_flag_lost
	call	nz, print_system
	ld		a, (read_report_status_work)
	bit		0, a
	ld		de, read_report_flag_timeout
	call	nz, print_system
	ret
;
; HLreg=0～65535を10進表示。全トラック×32件でも桁あふれさせない。
;-----------------------------------;
; 16ビット符号なし整数を10進数で表示する。
; 入力条件: HLreg: 0～65535。
; 戻り値: 表示のみ。IXregを数値変換の作業用に使用する。
;-----------------------------------;
read_report_print_word:
	ld		ix, read_report_number+5
	ld		(ix+CHR_POS), '$'
	dec		ix
read_report_word_digit:
	ld		de, 0
	ld		bc, 10
read_report_word_divide:
	or		a
	sbc		hl, bc
	jr		c, read_report_word_remainder
;
	inc		de
	jr		read_report_word_divide
;
read_report_word_remainder:
	add		hl, bc
	ld		a, l
	add		a, '0'
	ld		(ix+CHR_POS), a
	dec		ix
	ex		de, hl
	ld		a, h
	or		l
	jr		nz, read_report_word_digit
;
	inc		ix
	push	ix
	pop		de
	jp		print_system
;
read_report_heading: db 13,10,"Read error report",13,10,'$'
read_report_msg_track: db "Track=",'$'
read_report_msg_sector: db "  Sector R=",'$'
read_report_msg_track_fail: db "  Not saved: ",'$'
read_report_msg_info_fail: db "  Info unavailable: ",'$'
read_report_msg_info_total: db "  Unavailable tracks: ",'$'
read_report_msg_seek: db "Seek/restore",'$'
read_report_msg_id: db "Read ID",'$'
read_report_msg_buffer: db "Track buffer overflow",'$'
read_report_msg_id_over: db "More than 32 IDs",'$'
read_report_msg_index: db "INDEX timeout",'$'
read_report_msg_other: db "Track read",'$'
read_report_msg_status: db "  Status="
read_report_status_hex: ds 2
	db		'h', '$'
read_report_flag_ready: db " Not ready",'$'
read_report_flag_rnf: db " Sector not found",'$'
read_report_flag_crc: db " CRC",'$'
read_report_flag_lost: db " Lost data",'$'
read_report_flag_timeout: db " Timeout",'$'
read_report_msg_total_tracks: db "Tracks with errors: ",'$'
read_report_msg_total_sectors: db "  Sector errors: ",'$'
read_report_msg_failed_tracks: db "  Unsaved tracks: ",'$'
read_report_has_errors: db 0
read_report_sector_total: dw 0
read_report_failed_tracks: db 0
read_report_track_total: db 0
read_report_track: db 0
read_report_sectors_left: db 0
read_report_found: db 0
read_report_phase_work: db 0
read_report_status_work: db 0
read_report_pointer: dw 0
read_report_number: ds 6,0
;;	assert	READ_REPORT_END <= read_id_list
END
