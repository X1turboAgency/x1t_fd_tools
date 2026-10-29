;-----------------------------------;
; -i: トラックIDの構成だけを集計する。データやファイルは読み書きしない。
; 各トラックのIDを検出順に表示する。同じN別セクタ数の区間は最後にまとめる。
; 容量は128<<N（N=0～7）を32ビットで加算する。
; シリンダ・サーフェスは実際に取得したC/Hregの異なる値の個数。
;-----------------------------------;
; フォーマット生成用RAMを情報モードの集計保存に共用する。COMには埋め込まない。
; 1区間は開始・終了・成否・セクタ数の4バイトと、最大32種類のN/個数の組。
; トラックごとのセクタIDとバイト数を表示し、最後に構成と容量を集計する。
; (c)2026 X1turboAgency
; SPDX-License-Identifier: MIT
INFO_GROUP_START_POS         equ 00h
INFO_GROUP_END_POS           equ 01h
INFO_GROUP_KIND_POS          equ 02h
INFO_GROUP_SECTORS_POS       equ 03h
INFO_GROUP_PROFILE_POS       equ 04h
INFO_GROUP_SIZE              equ INFO_GROUP_PROFILE_POS+sector_status_buff_size*2
INFO_GROUP_BASE              equ format_data_buff
INFO_GROUP_END               equ INFO_GROUP_BASE+D88_TRACK_COUNT*INFO_GROUP_SIZE
INFO_ID_LINE_WIDTH           equ 79

;-----------------------------------;
; ID情報だけを順次取得し、各トラックの詳細と最後の集計を表示する。
; 入力条件: cli_parseと開始確認が完了し、FD・メディア・範囲を設定済み。
; 戻り値: 処理後は0000hへ移行する。取得不能時の継続と致命的異常の中断を区別する。
;-----------------------------------;
disk_info_mode:
	call	print_settings
	call	init_fdd_system
	call	read_report_init
	call	disk_info_init
disk_info_loop:
	call	disk_info_print_track_start
	call	COMMAND_READ_TRACK_INFO
	jr		c, disk_info_failed
;
	call	disk_info_collect
	call	disk_info_print_track_ids
	ld		a, 1
	ld		(disk_info_current_kind), a
	jr		disk_info_group
;
disk_info_failed:
	push	af
	push	af
	ld		de, disk_info_msg_track_unavailable
	call	print_system
	pop		af
	call	read_report_record_track
	pop		af
	call	fdd_check_abort
	jp		c, disk_info_access_error
;
	ld		a, 1
	ld		(disk_info_incomplete), a
	xor		a
	ld		(disk_info_current_kind), a
disk_info_group:
	call	disk_info_append_group
	call	next_track
	jr		nc, disk_info_loop
;
	call	disk_info_print_groups
	call	disk_info_summary
	call	read_report_print
	jp		0000h
;
disk_info_access_error:
	call	fdd_abort_command
	call	motor_off
	ld		de, fdd_msg_access
	call	print_system
	call	read_report_print
	jp		0000h
;
;-----------------------------------;
; 容量・形状・区間記録などの情報集計ワークを初期化する。
; 入力条件: なし。
; 戻り値: 集計ワークを初期化する。フラグは判定に使用しない。
;-----------------------------------;
disk_info_init:
	xor		a
	ld		(disk_info_run_active), a
	ld		(disk_info_group_count), a
	ld		(disk_info_incomplete), a
	ld		(disk_info_full_scan), a
	ld		(disk_info_cylinder_count), a
	ld		(disk_info_cylinder_count+1), a
	ld		(disk_info_surface_count), a
	ld		(disk_info_surface_count+1), a

	ld		hl, INFO_GROUP_BASE
	ld		(disk_info_group_write), hl

	ld		hl, 0
	ld		(disk_info_capacity), hl
	ld		(disk_info_capacity+2), hl

	ld		hl, disk_info_cylinders
	ld		de, disk_info_cylinders+1
	ld		bc, 511
	ld		(hl), a
	ldir

	ld		a, (start_track_no)
	or		a
	ret		nz
;
	ld		a, (end_track_no)
	ld		b, a
	ld		a, (cli_max_track)
	cp		b
	ret		nz
;
	ld		a, 1
	ld		(disk_info_full_scan), a
	ret
;
;-----------------------------------;
; read_id_listのC/H/Nを集計する。長さワークの+6には依存しない。
; IDのC/H/Nから検出形状・長さ別個数・容量を集計する。
; 入力条件: sector_numとread_id_listの生CHRN。
; 戻り値: 当該トラックの構成と、全体の検出数・容量を更新する。
;-----------------------------------;
disk_info_collect:
	xor		a
	ld		hl, disk_info_current_profile
	ld		de, disk_info_current_profile+1
	ld		bc, 255
	ld		(hl), a
	ldir

	ld		a, (sector_num)
	ld		(disk_info_ids_left), a
	ld		ix, read_id_list

;-----------------------------------;
; C/Hの既出判定、長さコード別個数と容量の加算を行う。
;-----------------------------------;
disk_info_collect_id:
	ld		l, (ix+ID_C_POS)
	ld		h, 0
	ld		de, disk_info_cylinders
	add		hl, de

	ld		a, (hl)
	or		a
	jr		nz, disk_info_collect_surface
;
	ld		(hl), 01h
	ld		hl, (disk_info_cylinder_count)

	inc		hl
	ld		(disk_info_cylinder_count), hl

disk_info_collect_surface:
	ld		l, (ix+ID_H_POS)
	ld		h, 0
	ld		de, disk_info_surfaces
	add		hl, de

	ld		a, (hl)
	or		a
	jr		nz, disk_info_collect_size
;
	ld		(hl), 1
	ld		hl, (disk_info_surface_count)
	inc		hl
	ld		(disk_info_surface_count), hl
disk_info_collect_size:
	ld		l, (ix+ID_N_POS)
	ld		h, 0
	ld		de, disk_info_current_profile
	add		hl, de
	inc		(hl)
	ld		a, (ix+ID_N_POS)
	cp		8
	jr		c, disk_info_add_size
;
	ld		a, 1
	ld		(disk_info_incomplete), a
	jr		disk_info_collect_next
;
disk_info_add_size:
	call	disk_info_sector_length
	ld		c, l
	ld		b, h
	ld		hl, (disk_info_capacity)
	add		hl, bc
	ld		(disk_info_capacity), hl
	ld		hl, (disk_info_capacity+2)
	ld		bc, 0
	adc		hl, bc
	ld		(disk_info_capacity+2), hl
disk_info_collect_next:
	ld		de, ID_SIZE
	add		ix, de
	ld		a, (disk_info_ids_left)
	dec		a
	ld		(disk_info_ids_left), a
	jr		nz, disk_info_collect_id
;
	ret

;-----------------------------------;
; Areg=N（0～7）、HLreg=1セクタのバイト数。呼び出し前に範囲を確認する。
; 生の長さコードから1セクタのバイト数を求める。
; 入力条件: Areg: 長さコード0～7。呼出し前に範囲検査済み。
; 戻り値: HLreg: 128 << 長さコード。Bregは作業用。
;-----------------------------------;
disk_info_sector_length:
	ld		hl, 128
	or		a
	ret		z
;
	ld		b, a
disk_info_sector_shift:
	add		hl, hl
	djnz	disk_info_sector_shift
;
	ret
;
;-----------------------------------;
; 同じセクタ構成の連続トラックを1区間にまとめる。
; 入力条件: 現在トラックの構成・取得可否と進行中区間のワーク。
; 戻り値: 区間を延長、または直前の区間を保存して新しい区間を開始する。
;-----------------------------------;
disk_info_append_group:
	ld		a, (disk_info_run_active)
	or		a
	jr		z, disk_info_new_group
;
	ld		a, (disk_info_current_kind)
	ld		b, a
	ld		a, (disk_info_run_kind)
	cp		b
	jr		nz, disk_info_change_group
;
	or		a
	jr		z, disk_info_extend_group
;
	ld		hl, disk_info_current_profile
	ld		de, disk_info_run_profile
	ld		b, 0
disk_info_compare_profile:
	ld		a, (de)
	cp		(hl)
	jr		nz, disk_info_change_group
;
	inc		de
	inc		hl
	djnz	disk_info_compare_profile
;
disk_info_extend_group:
	ld		a, (start_track_no)
	ld		(disk_info_run_end), a
	ld		hl, (disk_info_group_last)
	inc		hl
	ld		(hl), a
	ret
;
disk_info_change_group:
disk_info_new_group:
	ld		a, 1
	ld		(disk_info_run_active), a
	ld		a, (start_track_no)
	ld		(disk_info_run_start), a
	ld		(disk_info_run_end), a
	ld		a, (disk_info_current_kind)
	ld		(disk_info_run_kind), a
	ld		a, (sector_num)
	ld		(disk_info_run_sectors), a
	ld		hl, disk_info_current_profile
	ld		de, disk_info_run_profile
	ld		bc, 256
	ldir
	jp		disk_info_save_group
;
;-----------------------------------;
; 読取り直前に、通常ダンプと同じトラック番号の行を表示する。
; ID取得前に現在の読取りトラック番号を表示する。
; 入力条件: start_track_no。
; 戻り値: 表示のみ。フラグは判定に使用しない。
;-----------------------------------;
disk_info_print_track_start:
	ld		de, cmd03_msg
	call	print_system

	ld		a, (start_track_no)
	call	print_decimal
	jp		print_crlf

; ID検出順に #RR/バイト数 を表示する。Rは2桁の16進数、長さは10進数。
; N=0～7は128<<N。長さを計算できないNは?と表示し、最終集計でも区別する。
;-----------------------------------;
; IDの検出順を保って#番号/バイト数を表示する。
; 入力条件: sector_num、read_id_list。
; 戻り値: 表示のみ。79桁以内で折り返し、不明な長さは?とする。
;-----------------------------------;
disk_info_print_track_ids:
	ld		a, (sector_num)
	ld		(disk_info_ids_left), a
	xor		a
	ld		(disk_info_line_width), a
	ld		ix, read_id_list
disk_info_print_id:
	; 先頭の空白と#RR/で5桁。バイト数の桁数を加えて折返しを判定する。
	ld		a, (ix+ID_N_POS)
	ld		b, 8
	cp		3
	jr		c, disk_info_id_width_ready
;
	inc		b
	cp		7
	jr		c, disk_info_id_width_ready
;
	ld		b, 10
	jr		z, disk_info_id_width_ready
;
	ld		b, 6	; /?の場合。
disk_info_id_width_ready:
	ld		a, (disk_info_line_width)
	add		a, b
	cp		INFO_ID_LINE_WIDTH+1
	jr		c, disk_info_id_width_store
;
	ld		a, b
	push	af
	call	print_crlf
	pop		af
disk_info_id_width_store:
	ld		(disk_info_line_width), a

	ld		a, (ix+ID_R_POS)
	ld		hl, disk_info_sector_hex
	call	hex2_asc

	ld		de, disk_info_sector_text
	call	print_system
	ld		a, (ix+ID_N_POS)
	cp		8
	jr		nc, disk_info_id_unknown_length
;
	call	disk_info_sector_length
	; 10進表示はIXregを使うので、IDリストの現在位置を保存する。
	push	ix
	call	read_report_print_word
	pop		ix
	jr		disk_info_id_next
;
disk_info_id_unknown_length:
	ld		de, disk_info_msg_unknown_byte
	call	print_system
disk_info_id_next:
	ld		de, ID_SIZE
	add		ix, de
	ld		a, (disk_info_ids_left)
	dec		a
	ld		(disk_info_ids_left), a
	jp		z, print_crlf
;
	jr		disk_info_print_id
;
; 区間の構成はN/個数の組へ圧縮して保存する。IDの生データ領域は保持する。
;-----------------------------------;
; 進行中区間の構成をRAM上の区間リストへ保存する。
; 入力条件: 保存すべき有効なdisk_info_run_*と区間の書込み位置。
; 戻り値: 区間数と書込み位置を更新する。保存可否は呼出し側で判定する。
;-----------------------------------;
disk_info_save_group:
	ld		hl, (disk_info_group_write)
	ld		(disk_info_group_last), hl

	ld		de, INFO_GROUP_SIZE
	add		hl, de

	ld		(disk_info_group_write), hl
	ld		hl, (disk_info_group_last)
	ld		a, (disk_info_run_start)
	ld		(hl), a
	inc		hl
	ld		a, (disk_info_run_end)
	ld		(hl), a
	inc		hl
	ld		a, (disk_info_run_kind)
	ld		(hl), a
	inc		hl
	ld		a, (disk_info_run_sectors)
	ld		(hl), a
	inc		hl
	ex		de, hl
	ld		hl, disk_info_run_profile
	ld		bc, 0
disk_info_save_bucket:
	ld		a, (hl)
	or		a
	jr		z, disk_info_save_bucket_next
;
	push	af
	ld		a, c
	ld		(de), a
	inc		de
	pop		af
	ld		(de), a
	inc		de
disk_info_save_bucket_next:
	inc		hl
	inc		c
	djnz	disk_info_save_bucket
;
	ld		a, (disk_info_group_count)
	inc		a
	ld		(disk_info_group_count), a
	ret
;
; 全トラックの取得後に区間構成を復元し、まとめて表示する。
;-----------------------------------;
; 保存した区間構成を復元して、フォーマット集計を表示する。
; 入力条件: 全トラックの取得と最後の区間保存が完了していること。
; 戻り値: 表示のみ。区間表示用のワークを更新する。
;-----------------------------------;
disk_info_print_groups:
	ld		de, disk_info_msg_format_summary
	call	print_system
	ld		de, disk_info_msg_media
	call	print_system
	ld		a, (media_type)
	ld		de, str_media_2d
	or		a
	jr		z, disk_info_summary_media
;
	ld		de, str_media_2dd
	cp		DISK_TYPE_2DD
	jr		z, disk_info_summary_media
;
	ld		de, str_media_2hd
disk_info_summary_media:
	call	print_system
	call	print_crlf
	ld		a, (disk_info_group_count)
	or		a
	ret		z
;
	ld		(disk_info_groups_left), a
	ld		hl, INFO_GROUP_BASE
	ld		(disk_info_group_read), hl
;-----------------------------------;
; 区間レコードから構成を復元し、連続範囲を表示する。
;-----------------------------------;
disk_info_print_group:
	ld		hl, (disk_info_group_read)
	ld		de, INFO_GROUP_SIZE
	add		hl, de
	ld		(disk_info_group_read), hl
	or		a
	sbc		hl, de
	ld		a, (hl)
	ld		(disk_info_run_start), a
	inc		hl
	ld		a, (hl)
	ld		(disk_info_run_end), a
	inc		hl
	ld		a, (hl)
	ld		(disk_info_run_kind), a
	inc		hl
	ld		a, (hl)
	ld		(disk_info_run_sectors), a
	inc		hl
	push	hl
	xor		a
	ld		hl, disk_info_run_profile
	ld		de, disk_info_run_profile+1
	ld		bc, 255
	ld		(hl), a
	ldir
	pop		hl
	ld		a, (disk_info_run_kind)
	or		a
	jr		z, disk_info_group_ready
;
	ld		a, (disk_info_run_sectors)
	ld		(disk_info_profile_left), a
disk_info_restore_bucket:
	ld		e, (hl)
	ld		d, 0
	inc		hl
	ld		c, (hl)
	inc		hl
	push	hl
	ld		hl, disk_info_run_profile
	add		hl, de
	ld		(hl), c
	pop		hl
	ld		a, (disk_info_profile_left)
	sub		c
	ld		(disk_info_profile_left), a
	jr		nz, disk_info_restore_bucket
;
disk_info_group_ready:
	call	disk_info_flush_group
	ld		a, (disk_info_groups_left)
	dec		a
	ld		(disk_info_groups_left), a
	jp		nz, disk_info_print_group
;
	ret
;
;-----------------------------------;
; 現在の区間の範囲とセクタ構成、または取得不能を表示する。
; 入力条件: disk_info_run_*。
; 戻り値: 表示のみ。未開始の区間では何も表示しない。
;-----------------------------------;
disk_info_flush_group:
	ld		a, (disk_info_run_active)
	or		a
	ret		z
;
	ld		a, (disk_info_run_start)
	call	print_decimal
	ld		a, (disk_info_run_start)
	ld		b, a
	ld		a, (disk_info_run_end)
	cp		b
	jr		z, disk_info_group_label
;
	ld		de, str_dash
	call	print_system
	ld		a, (disk_info_run_end)
	call	print_decimal
disk_info_group_label:
	ld		de, disk_info_msg_track
	call	print_system
	ld		a, (disk_info_run_kind)
	or		a
	jr		nz, disk_info_print_profile
;
	ld		de, disk_info_msg_unavailable
	jp		print_system
;
disk_info_print_profile:
	ld		a, (disk_info_run_sectors)
	call	print_decimal
	ld		de, disk_info_msg_sectors
	call	print_system
	xor		a
	ld		(disk_info_bucket), a
	ld		(disk_info_distinct_sizes), a
	ld		hl, disk_info_run_profile
	ld		b, 0
disk_info_count_sizes:
	ld		a, (hl)
	or		a
	jr		z, disk_info_count_next
;
	ld		a, (disk_info_distinct_sizes)
	inc		a
	ld		(disk_info_distinct_sizes), a
disk_info_count_next:
	inc		hl
	djnz	disk_info_count_sizes
;
	xor		a
	ld		(disk_info_printed_size), a
disk_info_print_size:
	ld		a, (disk_info_bucket)
	ld		l, a
	ld		h, 0
	ld		de, disk_info_run_profile
	add		hl, de
	ld		a, (hl)
	or		a
	jp		z, disk_info_size_next
;
	ld		(disk_info_bucket_count), a
	ld		a, (disk_info_printed_size)
	or		a
	jr		z, disk_info_size_first
;
	ld		de, disk_info_msg_plus
	call	print_system
disk_info_size_first:
	ld		a, 1
	ld		(disk_info_printed_size), a
	ld		a, (disk_info_bucket)
	cp		8
	jr		nc, disk_info_size_unknown
;
	call	disk_info_sector_length
	call	read_report_print_word
	ld		de, disk_info_msg_bytes
	call	print_system
	jr		disk_info_size_suffix
;
disk_info_size_unknown:
	ld		de, disk_info_msg_n
	call	print_system
	ld		a, (disk_info_bucket)
	call	print_decimal
	ld		de, disk_info_msg_unknown
	call	print_system
disk_info_size_suffix:
	ld		a, (disk_info_distinct_sizes)
	cp		1
	jr		nz, disk_info_size_mixed
;
	ld		de, disk_info_msg_per_sector
	call	print_system
	jr		disk_info_size_next
;
disk_info_size_mixed:
	ld		de, disk_info_msg_times
	call	print_system
	ld		a, (disk_info_bucket_count)
	call	print_decimal
disk_info_size_next:
	ld		a, (disk_info_bucket)
	inc		a
	ld		(disk_info_bucket), a
	or		a
	jp		nz, disk_info_print_size
;
	jp		print_crlf
;
;-----------------------------------;
; 検出シリンダ数・面数と、全体または指定範囲の容量を表示する。
; 入力条件: 集計済みの形状・容量・未取得フラグ。
; 戻り値: 表示のみ。未取得・不明長があれば既知分の容量と区別する。
;-----------------------------------;
disk_info_summary:
	ld		de, disk_info_msg_geometry
	call	print_system
	ld		hl, (disk_info_cylinder_count)
	call	read_report_print_word
	ld		de, disk_info_msg_surfaces
	call	print_system
	ld		hl, (disk_info_surface_count)
	call	read_report_print_word
	call	print_crlf
	ld		a, (disk_info_full_scan)
	or		a
	ld		de, disk_info_msg_partial_capacity
	jr		z, disk_info_capacity_label
;
	ld		de, disk_info_msg_full_capacity
disk_info_capacity_label:
	call	print_system
	ld		a, (disk_info_incomplete)
	or		a
	jr		z, disk_info_capacity_known
;
	ld		de, disk_info_msg_incomplete
	call	print_system
	ld		de, disk_info_msg_known_capacity
	call	print_system
disk_info_capacity_known:
	ld		hl, disk_info_capacity
	call	disk_info_print_u32
	ld		de, disk_info_msg_byte_end
	jp		print_system
;
; HLregの32ビット値を10進数表示する。容量を16ビットで切り捨てない。
;-----------------------------------;
; メモリ上の32ビット符号なし整数を10進数で表示する。
; 入力条件: HLreg: リトルエンディアン4バイト値のアドレス。
; 戻り値: 表示のみ。元の値は変更しない。
;-----------------------------------;
disk_info_print_u32:
	ld		de, disk_info_dividend
	ld		bc, 4
	ldir
	ld		de, disk_info_number+10
	ld		a, END_CODE
	ld		(de), a
	dec		de
disk_info_decimal_digit:
	call	disk_info_divide10
	add		a, '0'
	ld		(de), a
	dec		de
	ld		hl, disk_info_dividend
	ld		a, (hl)
	inc		hl
	or		(hl)
	inc		hl
	or		(hl)
	inc		hl
	or		(hl)
	jr		nz, disk_info_decimal_digit
;
	inc		de
	jp		print_system
;

;-----------------------------------;
; 32回のビット除算。dividendを商に置き換え、Aregに余りを返す。
;-----------------------------------;
;-----------------------------------;
; 32ビット値を10で除算し、10進数の次の桁を求める。
; 入力条件: disk_info_dividend: リトルエンディアン4バイトの被除数。
; 戻り値: 同ワークを商に置換。Areg: 余り0～9。IXreg・Bregは作業用。
;-----------------------------------;
disk_info_divide10:
	ld		ix, disk_info_dividend
	ld		b, 32
	xor		a
disk_info_divide_bit:
	sla		(ix+U32_BYTE0_POS)
	rl		(ix+U32_BYTE1_POS)
	rl		(ix+U32_BYTE2_POS)
	rl		(ix+U32_BYTE3_POS)
	rla
	cp		10
	jr		c, disk_info_divide_next
;
	sub		10
	inc		(ix+U32_BYTE0_POS)
disk_info_divide_next:
	djnz	disk_info_divide_bit
;
	ret

;-----------------------------------;
;-----------------------------------;
;
disk_info_sector_text: db " #"
disk_info_sector_hex: ds 2
	db		"/",END_CODE
disk_info_msg_unknown_byte: db "?",END_CODE
disk_info_msg_track_unavailable: db " Unavailable",13,10,END_CODE
disk_info_msg_format_summary: db 13,10,"Format summary",13,10,END_CODE
disk_info_msg_media: db "Media: ",END_CODE
disk_info_msg_track: db " Track: ",END_CODE
disk_info_msg_unavailable: db "Unavailable",13,10,END_CODE
disk_info_msg_sectors: db "sector ,",END_CODE
disk_info_msg_bytes: db "byte",END_CODE
disk_info_msg_per_sector: db "/sector",END_CODE
disk_info_msg_plus: db " + ",END_CODE
disk_info_msg_times: db "x",END_CODE
disk_info_msg_n: db "N=",END_CODE
disk_info_msg_unknown: db "(unknown size)",END_CODE
disk_info_msg_geometry: db "Detected cylinders: ",END_CODE
disk_info_msg_surfaces: db "  Surfaces: ",END_CODE
disk_info_msg_full_capacity: db "Total capacity: ",END_CODE
disk_info_msg_partial_capacity: db "Selected capacity: ",END_CODE
disk_info_msg_incomplete: db "Unknown (missing IDs or unknown sector sizes)",13,10,END_CODE
disk_info_msg_known_capacity: db "Known ID capacity: ",END_CODE
disk_info_msg_byte_end: db " byte",13,10,END_CODE
disk_info_line_width: db 0
disk_info_group_count: db 0
disk_info_groups_left: db 0
disk_info_profile_left: db 0
disk_info_group_write: dw 0
disk_info_group_last: dw 0
disk_info_group_read: dw 0
disk_info_run_active: db 0
disk_info_run_start: db 0
disk_info_run_end: db 0
disk_info_run_kind: db 0
disk_info_run_sectors: db 0
disk_info_current_kind: db 0
disk_info_incomplete: db 0
disk_info_full_scan: db 0
disk_info_ids_left: db 0
disk_info_bucket: db 0
disk_info_bucket_count: db 0
disk_info_distinct_sizes: db 0
disk_info_printed_size: db 0
disk_info_cylinder_count: dw 0
disk_info_surface_count: dw 0
disk_info_capacity: ds 4,0
disk_info_dividend: ds 4,0
disk_info_number: ds 11,0
disk_info_current_profile: ds 256,0
disk_info_run_profile: ds 256,0
disk_info_cylinders: ds 256,0
disk_info_surfaces: ds 256,0
;;	assert INFO_GROUP_END <= 0cf00h
END
