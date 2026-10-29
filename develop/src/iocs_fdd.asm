;---------------------------------------------------------------;
; X1turboのFDC・DMA制御と、待ち時間制限付きのFD入出力を提供する。
;---------------------------------------------------------------;
; (c)2026 X1turboAgency
; SPDX-License-Identifier: MIT
FDC_ST_CMD			equ	0ff8h
FDC_TRACK			equ	0ff9h
FDC_SECTOR			equ	0ffah
FDC_DATA			equ	0ffbh
FDC_DRIVE			equ	0ffch
FDC_MFM				equ	0ffdh
FDC_2HD				equ	0ffeh
FDC_2DD				equ	0fffh

DMA_CONTROL			equ	01f80h

FDC_FORCE_INTERRUPT         equ 0d0h
FDC_WAIT_PAGES              equ 4	; 最大4×65536回の状態待ち（4MHzでおよそ4秒）。
FDC_INDEX_WAIT_PAGES        equ 4

FDC_CMD_RESTORE		equ	00h
FDC_CMD_SEEK		equ	01ch
FDC_MOTOR_ON		equ	080h
FDC_READ_ADRS		equ	0c0h
FDC_READ_SECTOR		equ	080h
FDC_READ_TRACK		equ	0e0h
FDC_WRITE_TRACK		equ	0f0h
FDC_WRITE_SECTOR	equ 0a0h

FDC_STATUS_MASK		equ	09bh	; FDCステータスレジスタのエラーマスク

FDC_STATUS_MASK_R	equ	081h	; セクタ読み込み

FDC_STATUS_MASK_SEEK	equ	081h	; FDCステータスレジスタのエラーマスク(SEEK)

FDC_STATUS_MASK_W	equ	0c1h	; セクタ書込み (+ライトプロテクト)

FDC_STATUS_MASK_TR	equ 0c1h	; 書込み時(フォーマット時) (+ライトプロテクト)



;-----------------------------------;
; ドライブモードの設定
; 2D/2DD , 2HD モードに設定
; Areg:
;	00h : 2Dモード
;	10h : 2DDモード
;	20h : 2HDモード
; DEreg: 破壊しないこと
;-----------------------------------;
set_fdd_mode:
	ld		bc, FDC_2DD		; 2D/2DD モード
	cp		DISK_TYPE_2HD
	jr		c, sfm_1
;
	ld		c, FDC_2HD & 0ffh	; 2HDモード
sfm_1:
	in		a,(c)

	; 倍密度
	ld		bc,	FDC_MFM
	in		a,(c)

	ret

;-----------------------------------;
; FDCコマンド発行してReady待ち
;	Areg: コマンド
;	Creg: ステータスレジスタマスク
; 戻り値:
;	Areg, Zflagにステータスレジスタの結果が入る。
;	Zflag: 準備オケー
;   nonZ: エラー (一定時間内に準備できなかった)
; 使用reg: BCreg
; 保存reg: HLreg,DEreg
;-----------------------------------;
set_fdd_cmd_status:
	push	bc
	ld		bc, FDC_ST_CMD
	out		(c),a
	pop		bc

;;	call	print_sector

;-----------------------------------;
; FDCステータスレジスタ取得。待ち超過時は停止する。
;	Creg: ステータスレジスタマスク
; 戻り値:
;	Areg, Zflagにステータスレジスタの結果が入る。
;	Zflag: 準備オケー
;   nonZ: エラー (一定時間内に準備できなかった)
; 使用reg: BCreg
; 保存reg: HLreg,DEreg
;-----------------------------------;
check_fdc_status:
	xor		a
	ld		(fdd_timed_out), a

	push	hl
	push	de
	ld		d, FDC_WAIT_PAGES
smo_3:
	ld		hl, 0000h
smo_1:
	ld		a, FDC_ST_CMD >> 8
	in		a,( FDC_ST_CMD & 0xff )

	ld		b,a		; save

	and		c
;;	and		09bh
	jr		z, smo_2

	dec		hl
	ld		a,h
	or		l
	jr		nz, smo_1

	dec		d
	jr		nz, smo_3

	ld		a, 1
	ld		(fdd_timed_out), a

	call	fdd_abort_command
	; TIME OUTや他のエラー
	; Areg: エラー内容
	; Zflag: なし
	ld		a,b
	or		a

smo_2:
	; エラーなし
	; Areg: 0
	; Zflag: あり
	pop		de
	pop		hl
	ret

; 待ち時間を超えたFDCコマンドとDMAを停止する。レジスタ・フラグは保存する。
;-----------------------------------;
; FDCを強制中断し、DMAを停止・リセットする。
; 入力条件: なし。
; 戻り値: AFreg・BCreg・HLregを保存する。DEregは変更しない。
;-----------------------------------;
fdd_abort_command:
	push	af
	push	bc
	push	hl
	ld		bc, FDC_ST_CMD
	ld		a, FDC_FORCE_INTERRUPT
	out		(c), a
	call	reset_dma
	pop		hl
	pop		bc
	pop		af
	ret
;
;-----------------------------------;
; 状態値と待ち超過フラグからFDチェック全体を中断するか判定する。
; 入力条件: Areg: FDC状態または独自エラーコード。fdd_timed_out。
; 戻り値: Cy=1: 中断が必要。Cy=0: 継続可能。Aregを保存する。
;-----------------------------------;
fdd_check_abort:
	push	af
	ld		a, (fdd_timed_out)
	or		a
	jr		nz, fdd_abort_yes
;
	pop		af
	push	af
	cp		RES_INDEX_TIMEOUT
	jr		z, fdd_abort_yes
;
	jr		nc, fdd_abort_no
;
	and		081h
	jr		nz, fdd_abort_yes
;
fdd_abort_no:
	pop		af
	or		a
	ret
;
fdd_abort_yes:
	pop		af
	scf
	ret

fdd_msg_access: db "Error: FDD not ready or access timed out.",13,10,END_CODE
fdd_timed_out: db 0

;-----------------------------------;
; 現在ドライブの物理トラック番号をワークから取得する。
; 入力条件: cur_drive: ドライブ番号0～3。
; 戻り値: Areg: 物理トラック番号。FFhは未初期化。HLregを保存する。
;-----------------------------------;
get_cur_track:
	push	hl
	call	calc_cur_track_adrs
	ld		a,(hl)
	pop		hl
	ret

;-----------------------------------;
; 現在ドライブのトラック位置を未初期化に戻す。
; 入力条件: cur_drive: ドライブ番号0～3。
; 戻り値: 現在トラックのワークにFFhを設定する。
;-----------------------------------;
init_cur_track:
	ld		a,0ffh
;-----------------------------------;
; 現在ドライブの物理トラック番号を保存する。
; 入力条件: Areg: 物理トラック番号。cur_drive。
; 戻り値: Areg・HLregを保存する。
;-----------------------------------;
set_cur_track:
	push	hl
	push	af
	call	calc_cur_track_adrs
	pop		af
	ld		(hl),a
	pop		hl
	ret

;-----------------------------------;
; 選択ドライブの現在トラックを保持するワークの位置を求める。
; 入力条件: cur_drive: ドライブ番号0～3。
; 戻り値: HLreg: 対象ワークのアドレス。
;-----------------------------------;
calc_cur_track_adrs:
	ld		a, (cur_drive)
	add		a, cur_track & 0ffh		; アライメントしてあるのでこれでオケー。
	ld		l,a
	ld		h, cur_track >> 8
	ret

;---------------------------------------------------------------;
; 現在のドライブ番号を設定する。
; 引数:
;	Areg: ドライブ番号 (0～3)
;---------------------------------------------------------------;
;-----------------------------------;
; 物理ドライブ番号を共通ワークに設定する。
; 入力条件: Areg: ドライブ番号0～3。
; 戻り値: cur_driveを更新。Aregとフラグは変更しない。
;-----------------------------------;
set_cur_drive:
	ld		(cur_drive),a
	ret

;---------------------------------------------------------------;
; 論理トラックを物理トラックに変換,ドライブ番号を加えて返す。(モーター制御用)
; 引数:
;	Ereg: 論理トラック番号 (2D: 0～79 2HD: 0～153)
; 戻り値:
;	Ereg: 物理トラック番号 (2D: 0～39 2HD: 0～76)
;	Areg: サーフェス + ドライブ番号
;---------------------------------------------------------------;
;-----------------------------------;
; 論理トラックを物理シリンダと面・ドライブ選択値へ変換する。
; 入力条件: Ereg: 論理トラック番号。cur_drive。
; 戻り値: Ereg: 物理シリンダ。Areg: 面とドライブ番号を組み合わせた値。
;-----------------------------------;
conv_real_track_no:
	srl		e

	ld		a, (cur_drive)
	ret		nc
;
	or		010h	; サーフェス
	ret


;---------------------------------------------------------------;
; 指定ドライブのモーターをOFF.
;---------------------------------------------------------------;
;-----------------------------------;
; 選択ドライブのモーターを停止する。
; 入力条件: cur_drive: ドライブ番号。
; 戻り値: BCregを保存する。Aregはドライブ番号。
;-----------------------------------;
motor_off:
	; モーターOFF
	push	bc
	ld		a, (cur_drive)
	ld		bc, FDC_DRIVE
	out		(c),a
	pop		bc

	ret

;---------------------------------------------------------------;
; 指定論理トラックへシークする。
;	Areg: 指定論理トラック (2D: 0～79 2HD: 0～153)
; 戻り値:
;	Areg, Zflagにステータスレジスタの結果が入る。
;	Zflag: 準備オケー
;   nonZ: エラー (一定時間内に準備できなかった)
;
; 破壊Reg:
;	BC,E
;---------------------------------------------------------------;
;-----------------------------------;
; 必要ならリストアし、指定論理トラックへシークする。
; 入力条件: Areg: 論理トラック番号。ドライブとメディアは設定済み。
; 戻り値: Z: 成功。NZ: エラー。Areg: 状態値。
;-----------------------------------;
fdd_seek:
	ld		e,a

	call	get_cur_track
	cp		0ffh
	jr		nz, fs_1
;
	; まだドライブが初期化されていないのでリストアを発行する。

	; モーターON
	ld		bc, FDC_DRIVE
	ld		a, (cur_drive)
	or		FDC_MOTOR_ON
	out		(c),a

; --
;	; Restore-0 msg.
;;	push	de
;;	ld		de,msg_restore_0
;;	call	text_puts
;;	pop		de
; --

	ld		c, FDC_STATUS_MASK_SEEK
	call	check_fdc_status
	jr		nz, fdd_restore_err_exit
;

; --
;	; Restore-0 msg.
;;	push	de
;;	ld		de,msg_restore_1
;;	call	text_puts
;;	pop		de
; --

	; リストア
	ld		a,FDC_CMD_RESTORE
	ld		c,FDC_STATUS_MASK
	call	set_fdd_cmd_status
	jr		nz, fdd_restore_err_exit

	; 現在のトラックを0にする。
	xor		a
	call	set_cur_track

fs_1:
	; Ereg: 目標論理トラック
	; Areg: 現在の物理トラック
	push	af

	; 論理トラックを物理トラックに変換する。
	call	conv_real_track_no
	or		FDC_MOTOR_ON
	ld		bc, FDC_DRIVE
	out		(c),a
	pop		af

	; Ereg: 目標物理トラック
	ld		bc, FDC_DATA
	out		(c),e

	; Areg: 現在の物理トラック
	ld		bc, FDC_TRACK
	out		(c),a

	; シークを発行
	ld		a,FDC_CMD_SEEK
	ld		c,FDC_STATUS_MASK_SEEK
	call	set_fdd_cmd_status
	jr		nz, fdd_seek_err

	; シークに成功したら現在の物理トラックを保存
	ld		a,e
	call	set_cur_track

	; コマンド成功
	xor		a
	ret

fdd_seek_err:
;;	bit		4,a
;;	jr		z, fd_se_ex_1
;
	; SEEK ERROR

	push	af

IF TOOL_RESTORE
	; DEregのメッセージを表示する。
	push	de
	ld		de,msg_seek_error_ck
	call	print_system
	pop		de
ENDIF

	; SEEK ERROR が発生している時は、現在のトラックを無効化する。
	call	init_cur_track

	pop		af

	; Aregは保持される
IF TOOL_RESTORE
	call	print_disk_stat
ENDIF

fd_se_ex_1:
	or		a
	ret

fdd_restore_err_exit:
IF TOOL_RESTORE
	push	af
	; DEregのメッセージを表示する。
	ld		de,msg_restore_error
	call	print_system
	pop		af

	; Aregは保持される
	call	print_disk_stat

ENDIF
	or	a
	ret

msg_restore_0:
	db		"RESTORE_0:" ,0dh,0

msg_restore_1:
	db		"RESTORE_1:" ,0dh,0

msg_restore_error:
	db		"Restore failed:" ,0dh,0ah,END_CODE

msg_seek_error:
	db		"SEEK ERROR RESTORE:" ,0dh,0

msg_seek_error_ck:
	db		"Seek failed:" ,0dh,0ah,END_CODE

msg_seek_error_exit:
	db		"SEEK ERROR EXIT:" ,0dh,0

;---------------------------------------------------------------;
; FDDに対してリードアドレスを発行する。
; 重複チェックを行って1トラック内のセクタIDリストを作成する。
; 戻り値:
;	Areg, Zflagにステータスレジスタの結果が入る。
;	Zflag: 準備オケー
;   nonZ: エラー (一定時間内に準備できなかった)
;
;	Dreg: リードアドレス個数
;---------------------------------------------------------------;
;-----------------------------------;
; INDEX待ち後にIDを列挙し、同じIDの再検出で一周を判断する。
; 入力条件: 対象トラックへType-Iコマンドでシーク済み。
; 戻り値: Z: 成功、Dreg=ID個数。NZ: FDC異常・INDEX待ち超過・32件超過。
;-----------------------------------;
fdd_read_id:
	; ここに来る前にシーク等でType1のコマンドを実行しておく必要あり。

	; read_id_listを0ffhで埋めておく。
	ld		hl, read_id_list
	ld		de, read_id_list+1
	ld		bc,0100h-1
	ld		(hl),0ffh
	ldir

	; INDEXを一定時間待つ。未検出時はアクセス中断として戻す。
	ld		bc, FDC_ST_CMD
	ld		d, FDC_INDEX_WAIT_PAGES
	ld		hl, 0
fri_1:
	in		a, (c)
	and		02h
	jr		nz, fri_index_ready
;
	dec		hl
	ld		a, h
	or		l
	jr		nz, fri_1
;
	dec		d
	jr		nz, fri_1
;
	ld		a, 1
	ld		(fdd_timed_out), a
	call	fdd_abort_command
	ld		a, RES_INDEX_TIMEOUT
	or		a
	ret
;
;-----------------------------------;
; INDEXを検出したので、重複IDが現れるまで列挙する。
;-----------------------------------;
fri_index_ready:
	; 個数と格納位置(L)の初期化
	ld		de, 0
fri_6:
	; セクターIDをひとつ読み込み
	call	read_disk_id_1
	ret		nz		; err.

	; リスト個数が0かどうか
	inc		d
	dec		d
	jr		z, fri_2

	push	de
	call	find_sector_id
	pop		de
	jp		z, fri_4	; 見つかった(=1周した=終了)

; リスト内に無かったので追加。
fri_2:
	ld		a,d
	cp		32
	jr		c,fri_add_id
	ld		a,RES_ID_OVER
	or		a
	ret
fri_add_id:
	; リストにID(8byte)を追加。
	push	de
	ld		d, read_id_list >> 8
	ld		hl, read_id_buff
	ld		bc,8
	ld		a,c
	ldir
	pop		de

	; 格納アドレス(Eregのみ)を+8
	add		a,e
	ld		e,a

	; 個数を+1
	inc		d

	jp		fri_6

fri_4:
	; 一致して一周したので終了。
	xor		a		; 正常終了
	ret


; ---
;-----------------------------------;
; 読込み済みIDの先頭6バイトが登録リスト内に存在するか調べる。
; 入力条件: Dreg: 登録ID数（1以上）。read_id_buff、read_id_list。
; 戻り値: Z: 同じIDあり。NZ: 見つからない。
;-----------------------------------;
find_sector_id:
	; 作成したリスト内に同じセクターIDがあるかどうかをチェック
	; Dreg: セクタID登録数

	ld		hl, read_id_list

fsi_3:
	ld		bc, read_id_buff
	ld		e, 06h

	push	hl

fsi_2:
	ld		a,(bc)
	inc		bc
	cp		(hl)
	jp		nz, fsi_1	; 違うので次へ

	inc		hl

	dec		e
	jp		nz, fsi_2

	; 一致したものがある。
	pop		hl

	ret

; 次のセクタIDへ。
fsi_1:
	pop		hl

	ld		bc, 0008h
	add		hl,bc

	dec		d
	jp		nz, fsi_3
;
	; 見つからなかった。
	dec		b	; NZフラグセット
	ret


; IDを一つ読み込み
;-----------------------------------;
; Read Addressを1回実行し、IDと計算済みのセクタ長を取得する。
; 入力条件: 対象トラックへシーク済み。
; 戻り値: Z: 正常。NZ: FDCエラー。read_id_buffにIDと長さを格納。
;-----------------------------------;
read_disk_id_1:
	; read-IDバッファを念のためクリア
	ld		hl, 0
	ld		(read_id_buff+0),hl
	ld		(read_id_buff+2),hl
	ld		(read_id_buff+4),hl
	ld		(read_id_buff+6),hl

	; DMA読み込み対象アドレスをセット
	ld		hl, read_id_buff
	ld		(dma_read_adrs), hl

	ld		hl, dma_read_id_data
	call	set_dma

	ei

	ld		a, FDC_READ_ADRS
	ld		c, FDC_STATUS_MASK_SEEK
	call	set_fdd_cmd_status
	ld		a, b
	and		09dh	; CRC・Lost Data・RNF・Not Ready・Busy

	push	af
	call	reset_dma

	; 高速化のため read-IDから長さを求めておく。
	ld		a,(read_id_sector_len)	; セクタ長(0-3)
	call	get_sector_length
	ld		(read_id_buff+6),bc
	pop		af
;	jr		nz, fri_2		; err.

	ret

;---------------------------------------------------------------;
; セクタIDのセクタ長からbyte数を求める。
; 引数:
;	Areg: 0-3
; 戻り値:
;	BCreg: 128,256,512,1024
;---------------------------------------------------------------;
;-----------------------------------;
; IDの長さコードをバイト数へ変換する。
; 入力条件: Areg: 長さコード（0、1、2、3以上）。
; 戻り値: BCreg: 128、256、512、1024。3以上は1024として扱う。
;-----------------------------------;
get_sector_length:
	ld		bc, 0080h
	or		a
	ret		z

	ld		bc, 0100h
	dec		a
	ret		z

	ld		b, 0200h >> 8
	dec		a
	ret		z

	ld		b, 0400h >> 8
	ret

;---------------------------------------------------------------;
; 指定セクタを読み込む。
;	Areg: セクタ番号 (0～ )
;	HLreg: 読み込みバッファアドレス
;	BCreg: 読み込みの長さ
; 戻り値:
;	Areg, Zflagにステータスレジスタの結果が入る。
;	Zflag: 準備オケー
;   nonZ: エラー (一定時間内に準備できなかった)
; 保存reg: DEreg
;---------------------------------------------------------------;
;-----------------------------------;
; DMAで指定セクタのデータを読み取る。
; 入力条件: Areg: セクタ番号。HLreg: 読込み先。BCreg: バイト数（1以上）。
; 戻り値: Z: 正常。NZ: 読取り異常。Areg: 削除マークを含む生状態。DEreg保存。
;-----------------------------------;
fdd_read_sector:
	push	af

	; DMA読み込み先アドレスをセット
	ld		(dma_read_sector_adrs), hl

	; 読み込み長をセット
	dec		bc
	ld		(dma_read_sector_length),bc

	ld		hl, dma_read_sector_data
	call	set_dma

	pop		af

	ei

	; セクタ番号
	ld		bc, FDC_SECTOR
	out		(c),a

	ld		a, FDC_READ_SECTOR
	ld		c, FDC_STATUS_MASK_R
	call	set_fdd_cmd_status

	ld		a,b			; raw Type-II FDC status from check_fdc_status
	and		09dh		; not-ready/RNF/CRC/lost-data/busy
	ld		a,b			; keep DDAM and raw status, preserve Z
	push	af
	call	reset_dma
	pop		af

	ret

;---------------------------------------------------------------;
; 指定セクタに書き込む
;	Areg: セクタ番号 (0～ )
;	HLreg: 書込みデータアドレス
;	BCreg: 書込みの長さ
; 戻り値:
;	Areg, Zflagにステータスレジスタの結果が入る。
;	Zflag: 準備オケー
;   nonZ: エラー (一定時間内に準備できなかった)
; 保存reg: DEreg
;---------------------------------------------------------------;
;-----------------------------------;
; DMAで指定セクタへデータを書き込む。
; 入力条件: Areg: セクタ番号。HLreg: データ先頭。BCreg: バイト数（1以上）。write_deleted。
; 戻り値: Z: 正常。NZ: 書込み異常。Areg: マスク済みの状態値。DEreg保存。
;-----------------------------------;
fdd_write_sector:
	push	af

	; 書き込むデータアドレスをセット
	ld		(dma_write_data_adrs), hl

	; 書込み長をセット
	dec		bc
	ld		(dma_write_data_leng),bc

	ld		hl, dma_write_data
	call	set_dma

	pop		af

	ei

	; セクタ番号
	ld		bc, FDC_SECTOR
	out		(c),a

	ld		a,(write_deleted)
	and		1
	or		FDC_WRITE_SECTOR
	ld		c,1
	call	set_fdd_cmd_status
	ld		a,b
	and		0fdh	; 書込み保護・Lost Data・RNF等を検査

	push	af
	call	reset_dma
	pop		af

	ret

;---------------------------------------------------------------;
; 指定トラックを読み込む。
;	HLreg: 読み込みバッファアドレス
;	BCreg: 読み込みの長さ
; 戻り値:
;	Areg, Zflagにステータスレジスタの結果が入る。
;	Zflag: 準備オケー
;   nonZ: エラー (一定時間内に準備できなかった)
;---------------------------------------------------------------;
;-----------------------------------;
; DMAで現在トラックをまとめて読み取る。
; 入力条件: HLreg: 読込み先。BCreg: バイト数（1以上）。ドライブ設定済み。
; 戻り値: Z: 状態待ち完了。NZ: 待ち超過。Areg: 状態待ちの結果。
;-----------------------------------;
fdd_read_track:
	; DMA読み込み先アドレスをセット
	ld		(dma_read_sector_adrs), hl

	; 読み込み長をセット
	dec		bc
	ld		(dma_read_sector_length),bc

	ld		hl, dma_read_sector_data
	call	set_dma

	ei

	ld		a, FDC_READ_TRACK
	ld		c, FDC_STATUS_MASK
	call	set_fdd_cmd_status

	push	af
	call	reset_dma
	pop		af

	ret

;---------------------------------------------------------------;
; トラックにデータを書き込む。
;	HLreg: 書込むデータアドレス
;	BCreg: 書込みの長さ
; 戻り値:
;	Areg, Zflagにステータスレジスタの結果が入る。
;	Zflag: 準備オケー
;   nonZ: エラー (一定時間内に準備できなかった)
;---------------------------------------------------------------;
;-----------------------------------;
; DMAでトラックを書き込み、通常エラー時は最大5回試す。
; 入力条件: HLreg: フォーマットデータ。BCreg: バイト数（1以上）。
; 戻り値: Z: 成功。NZ: エラー。Areg: 状態値。未準備・待ち超過は再試行しない。
;-----------------------------------;
fdd_write_track:
	; FDDに書き込むデータアドレスをセット
	ld		(dma_write_data_adrs), hl

	; 書込み長をセット
	dec		bc
	ld		(dma_write_data_leng),bc

	di

	ld		b,05h	; リトライ回数

	ei	; 意味ある？

;-----------------------------------;
; DMA設定とWrite Trackを再発行し、致命的異常では再試行を打ち切る。
;-----------------------------------;
fwt_2:
	push	bc

	; フォーマットデータをDMAにセット。
	ld		hl, dma_write_data
	call	set_dma

	ld		a, FDC_WRITE_TRACK
	ld		c,1	; WriteTrack用
	call	set_fdd_cmd_status
	ld		a,b
	and		0fdh	; 書込み保護・Lost Data・RNF等を検査

	push	af
	call	reset_dma
	pop		af

	pop		bc

	ret		z		; エラーなし
	call	fdd_check_abort
	ret		c		; 未準備/タイムアウトでは再発行しない。

	; err.
;;	ld		c,a			; save

;;	and		083h
;;	cp		002h		; 'DATA REQUEST' のみ立っている？

;;	ld		a,c

;;	jr		nz, fwt_1

	djnz	fwt_2

	; リトライしてもダメだった。

; それ以外のエラー
fwt_1:
	or		a
	ret

;-----------------------------------;
; DMAの停止・リセット用設定列を出力する。
; 入力条件: なし。
; 戻り値: DMAをリセットする。Areg・BCreg・HLregを作業用に使用する。
;-----------------------------------;
reset_dma:
	ld		hl, dma_reset_data

;-----------------------------------;
; DMAに対してデータを設定する。
;	HLreg: 設定データ (先頭にデータ個数)
; 入力条件: HLreg: 先頭1バイトが個数（1以上）の設定列。
; 戻り値: HLreg: 設定列の直後。Areg=0。BCreg: DMAポート。
;-----------------------------------;
set_dma:
	ld		a,(hl)
	inc		hl
	ld		bc, DMA_CONTROL
sd_1:
	push	af
	ld		a,(hl)
	out		(c),a
	inc		hl

	pop		af

	dec		a
	jr		nz, sd_1

	ret


dma_read_id_data:
	db		dma_read_id_data_end-$-1	; 個数
	db		083h, 07dh, 0fbh, 00fh
	db		005h, 000h		; データ長(6-1)
	db		02ch, 010h, 080h, 08dh
dma_read_adrs:
	db		000h, 090h		; 格納アドレス (09000h) … アドレスはDMA設定時に書換え
	db		092h, 0cfh, 087h
dma_read_id_data_end:

dma_reset_data:
	db		dma_reset_data_end-$-1	; 個数
	db		083h
dma_reset_data_end:

; --
dma_read_sector_data:
	db		dma_read_sector_data_end-$-1	; 個数
	db		083h, 07dh, 0fbh, 00fh
dma_read_sector_length:	
	db		0ffh, 000h		; データ長(256-1)
	db		02ch, 010h, 080h, 08dh
dma_read_sector_adrs:
	db		000h, 091h		; 格納アドレス (09100h) … アドレスはDMA設定時に書換え
	db		092h, 0cfh, 087h
dma_read_sector_data_end:

; --
dma_write_data:
	db		dma_write_data_end-$-1	; 個数
	db		083h		; WR6 ディスイネーブル
	db		079h		; WR0 ポートB→A転送 後続に開始Aアドレス,長さ
dma_write_data_adrs:
	db		000h, 0c0h			; 格納アドレス (0c000h) … アドレスはDMA設定時に書換え
dma_write_data_leng:
	db		0afh, 028h			; データ長(28b0h-1)

	db		014h	; WR1: ポートA (可変,インクリメント,メモリ)

	db		028h	; WR2: ポートB (固定,デクリメント,I/O)

	db		080h	; WR3: サーチ用 特に指定なし

	db		08dh	; WR4: FD用にバイトモード, ポートB開始アドレス(L,H)後続データあり

	; ポートBアドレス(0ffbh)
	db		0fbh, 00fh

	db		092h	; WR5: FDDの場合はd3=0,Wait受付,EOBで終決

	db		0cfh	; WR6: Srcアドレス(ポートA)をレジスタにロード,カウンタをセット
	db		005h	; WR0: 転送モード,ポートA→B再設定,開始アドレス,サイズは指定しない。

	db		0cfh	; WR6: Srcアドレス(ポートB)をレジスタにロード,カウンタをセット
	db		087h	; WR6: 転送開始
dma_write_data_end:

;---------------------------------------------------------------;

; 現在のドライブ: 0,1,2,3
cur_drive:
	ds	1

; 物理トラック番号 (2D: 0～39 2HD: 0～76)
	align 4
cur_track:
	ds	4

;-----------------------------------;
; ドライブ別トラック位置とFDD待ち超過フラグを初期化する。
; 入力条件: なし。
; 戻り値: 初期化のみ。フラグは判定に使用しない。
;-----------------------------------;
init_fdd_system:
	xor		a
	ld		(fdd_timed_out), a
	ld		(cur_drive),a

	; 初期化のため現在のトラック番号は 0ffにしておく。
	ld		hl, 0ffffh
	ld		(cur_track+0),hl
	ld		(cur_track+2),hl

	ret

read_id_buff:
	ds		3
read_id_sector_len:
	ds		5

write_deleted:
	db 0

write_adrs_str:
	db "@ dma-adrs "
write_adrs_str_hex:
	ds	4
	db  0dh,00h

leng_info_str:
	db "@ fo-leng "
leng_info_str_hex:
	ds	4
	db	0dh,00h

;---------------------------------------------------------------;
END

