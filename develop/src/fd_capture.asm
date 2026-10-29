;-----------------------------------;
; ディスク読出しコマンド
; FDのトラックIDを取得し、検出順にセクタデータと状態を読み取る。
;-----------------------------------;
; (c)2026 X1turboAgency
; SPDX-License-Identifier: MIT
;-----------------------------------;
; トラックIDを取得し、その順にセクタデータを読み取る。
; 入力条件: FD・メディア・現在トラックの設定。
; 戻り値: Cy=0: 取得完了。Cy=1: トラック取得失敗。各セクタの状態も保存する。
;-----------------------------------;
COMMAND_READ_DISK:
	call	capture_read_track_ids
	ret		c
;
	;
	; セクタIDリストに合わせてセクター読み込み
	;

	push	de ; preserve D: sector count while clearing RAM
	ld		hl, read_track_buff
	ld		de, read_track_buff+1
	ld		bc, read_track_buff_max-read_track_buff-1
	ld		(hl), 0
	ldir
	pop		de
	ld		ix, read_id_list
	ld		iy, sector_status_buff
	ld		hl, read_track_buff

crd_1:
	; セクタの長さ(byte単位)
	ld		c, (ix+ID_LENGTH_L_POS)
	ld		b, (ix+ID_LENGTH_H_POS)

	; バッファオーバをチェック。
	; 読込み前に読込み後のアドレスをチェックしているのでバッファオーバは無い。
	push	hl
	add		hl, bc
	ld		a, h
	cp		read_track_buff_max >> 8
	pop		hl
	jp		nc, capture_buffer_over

	ld		a, (ix+ID_R_POS) ; セクタ番号

	push	bc
	push	hl
	call	fdd_read_sector
	pop		hl
	pop		bc

	; ディスク読出しステータスを格納する。
	ld		(iy+SECTOR_STATUS_POS), a
	push	af
	inc		iy
	ld		a, (capture_sectors_read)
	inc		a
	ld		(capture_sectors_read), a
	pop		af
	call	fdd_check_abort
	jp		c, capture_access_error
;
;;	jr		nz, send_error_response_disk_stat

	; データ格納アドレスをセクタ長進める。
	add		hl, bc

	ld		bc, ID_SIZE
	add		ix, bc

	dec		d
	jr		nz, crd_1
;
	;
	; セクタを全部読んだ後にセクタ番号を表示する。
	;

	call	print_space ; 行頭に空白を入れる

	ld		de, (sector_num) ; Eregに直接読み込む

	ld		ix, read_id_list
	ld		iy, sector_status_buff
crd_2:
	ld		a, (iy+SECTOR_STATUS_POS) ; Read Status
	and		09dh ; DDAM (bit5) is not a read error
	; このタイミングでReadStatusの結果がZflagに入る。

	ld		a, (ix+ID_R_POS) ; セクタ番号

	; Z: エラーなし
	; NZ: エラー
	; print_sector, print_sctor_NG はフラグまで保持するので、
	; 以下の呼び分けで問題なし。
	call	z, print_sector
	call	nz, print_sector_NG

	ld		bc, ID_SIZE
	add		ix, bc
	inc		iy

	dec		e
	jr		nz, crd_2

	; 改行
	call	print_crlf

	; トラックデータサイズを求める。
	ld		bc, read_id_list
	or		a
	sbc		hl, bc

	; モーターOff.
	call	motor_off

	; トラックデータサイズをBCregへ。
	ld		b, h
	ld		c, l

	; BCreg データ転送サイズ

	; 転送データアドレス
	ld		hl, read_id_list

	; セクタ数
	; 読取り後のパラメータを返す。
	; 7bit目にデータ圧縮あり/なしを付ける。
	; ここでは圧縮指定無しなので、そのまま値を返す。
	xor		a
	ld		(capture_error_phase), a
	ld		a, (sector_num)
	or		a ; CF=0: complete track capture

crd_4:

	ret

;-----------------------------------;
; IDだけを取得する。セクタデータのDMAやD88 I/Oには進まない。
;-----------------------------------;
;-----------------------------------;
; トラックIDだけを取得し、セクタデータは読み取らない。
; 入力条件: FD・メディア・現在トラックの設定。
; 戻り値: Cy=0: ID取得成功。Cy=1: 取得失敗。sector_numにID個数。
;-----------------------------------;
COMMAND_READ_TRACK_INFO:
	call	capture_read_track_ids
	ret		c
;
	call	motor_off
	xor		a
	ret
;
;-----------------------------------;
; ドライブ選択・シーク・ID取得とバッファ容量の確認を行う。
; 入力条件: drive_no、media_type、start_track_no、cli_info。
; 戻り値: Cy=0: sector_numとIDリストを設定。Cy=1: 失敗段階と状態値を設定。
;-----------------------------------;
capture_read_track_ids:
	xor		a
	ld		(capture_sectors_read), a
	ld		(sector_num), a
	ld		a, READ_PHASE_SEEK
	ld		(capture_error_phase), a
	; DriveNo,メディア(2D/2HD),読出しトラック番号の設定,メッセージ表示
	ld		a, (cli_info)
	or		a
	jr		nz, capture_info_select
;
	ld		de, cmd03_msg
	call	setup_drive_param
	jr		capture_seek
;
capture_info_select:
	call	select_drive_param
	ld		a, (start_track_no)
capture_seek:

	; 読み取り- の前にシーク(TypeI)
	call	fdd_seek
	jp		nz, send_error_resposne_motor_off

	; ディスクアドレスの読み込み
	; Dreg: セクタ数
	ld		a, READ_PHASE_ID
	ld		(capture_error_phase), a
	call	fdd_read_id
	jp		nz, send_error_response_disk_stat

	ld		a, d
	or		a
	jr		nz, capture_id_count_present
;
	ld		a, 010h ; IDがない場合は未検出として扱う。
	jp		send_error_response_disk_stat
;
capture_id_count_present:
	cp		33
	jr		c, capture_id_count_valid
;
	ld		a, RES_ID_OVER
	jp		send_error_response_disk_stat
;
capture_id_count_valid:
	ld		(sector_num), a

	xor		a
	ld		(capture_error_phase), a
	ret
;
;-----------------------------------;
; エラーレスポンスを返す。詳細表示は全トラックの処理終了後に行う。
;	引数:
;		Areg: エラー内容 (=0以外)
;-----------------------------------;
send_error_response_disk_stat:
	cp		RES_ID_OVER
	jr		nz, capture_check_index
;
	ld		a, READ_PHASE_ID_OVER
	ld		(capture_error_phase), a
	ld		a, RES_ID_OVER
	jr		send_error_resposne_motor_off
;
capture_check_index:
	cp		RES_INDEX_TIMEOUT
	jr		nz, send_error_resposne_motor_off
;
	ld		a, READ_PHASE_INDEX
	ld		(capture_error_phase), a
	ld		a, RES_INDEX_TIMEOUT
	jr		send_error_resposne_motor_off
;
capture_access_error:
	ld		b, a
	ld		a, READ_PHASE_OTHER
	ld		(capture_error_phase), a
	ld		a, b
	jr		send_error_resposne_motor_off
;
capture_buffer_over:
	ld		a, READ_PHASE_BUFFER
	ld		(capture_error_phase), a
	ld		a, RES_READ_OVER

;-----------------------------------;
; エラーレスポンスを返す。FDDのモーター停止
;	引数:
;		Areg: エラー内容 (=0以外)
;-----------------------------------;
send_error_resposne_motor_off:
	push	af
	; モーターOff.
	call	motor_off
	pop		af
	scf		; CF=1: このトラックは未収録とし、メインで次へ進む
	ret


capture_error_phase: db 0
capture_sectors_read: db 0

END
