;---------------------------------------------------------------;
;	システム定義
; LSX-Dodgersの呼出し番号、X1のI/O、バッファと構造体オフセットを定義する。
;---------------------------------------------------------------;
; (c)2026 X1turboAgency
; SPDX-License-Identifier: MIT

; LSX-Dodgers Define.

SYSTEM					equ		0005h		; システムコール
FCB1					equ		005Ch		; 1番目の引数のFCB
FCB2					equ		006Ch		; 2番目の引数のFCB
DTA1					equ		0080h

CMD_FILE_CREATE             equ     016h
CMD_FILE_RENAME             equ     017h
CMD_GET_CURRENT_DRIVE       equ     019h
CMD_WRITE_RAND_BLOCK        equ     026h
CMD_FLUSH                   equ     05fh

CMD_FILE_OPEN			equ		00fh
CMD_SET_DATA_ADRS		equ		01ah
CMD_READ_RAND_BLOCK		equ		027h
CMD_FILE_CLOSE			equ		010h
CMD_CHAR_IN                 equ     001h
CMD_CHAR_OUT                equ     002h
CMD_STR_OUT				equ		009h
CMD_DOS_VERSION            equ     06fh
LSX_MACHINE_X1             equ     000h

CMD_CHECK_KEY			equ		00bh

; X1/turbo システム
INT_VECTOR1_CTC			equ		00058h	; CZ-8FB01 v1.0 / v2.0
INT_VECTOR2_CTC			equ		00018h	; CZ-8FB02

CRTC_ADRS				equ		01800h
PSG_ADRS				equ		01c00h
VBLANK_SIGNAL			equ		01a01h
CTC_TURBO_ADRS			equ		01fa0h
CTC_X1_ADRS				equ		00704h

CTC_VSYNC_FRAME			equ		167

TEXT_VRAM				equ		03000h
KANJI_VRAM				equ		03800h

TEXT_VRAM_CK			equ		TEXT_VRAM + 07d0h
KANJI_VRAM_CK			equ		KANJI_VRAM + 07d0h

; DiskType
DISK_TYPE_2D		equ	000h
DISK_TYPE_2DD		equ	010h
DISK_TYPE_2HD		equ	020h

; 各フォーマットデータの最大長
FORMAT_DATA_2HD_MAX_SIZE	equ	10400
FORMAT_DATA_2D_MAX_SIZE		equ 6240

;
; 転送用データバッファ
;

trans_data_buff		equ	0a000h
trans_data_size		equ 03000h

;
; ROM読出しバッファ
;

cg_rom_buff			equ	0a000h


;
; ディスクフォーマット(ライトトラック)データ生成エリア
;

format_data_buff	equ 0a100h
;;write_track_buff	equ 0a000h


compress_buff		equ	0a000h

; レスポンスで圧縮指定の場合
compress_mask		equ	080h

;
; ディスク読み込み/書込み関係
;

; 書込み時のバッファ (最大 12KB)
write_buff			equ 04000h

write_id_list		equ	write_buff

; 書込み時のデータバッファ
write_data_buff		equ	write_buff + 0100h


; セクタIDリスト1件の構造。Read AddressのCHRN・CRCと計算済みの長さ。
; POSは各項目のバイトオフセット。長さはリトルエンディアン。
ID_C_POS                    equ     00h         ; シリンダ番号（C）
ID_H_POS                    equ     01h         ; サーフェス番号（H）
ID_R_POS                    equ     02h         ; セクタ番号（R）
ID_N_POS                    equ     03h         ; セクタ長コード（N）
ID_CRC0_POS                 equ     04h         ; 受信CRCの先頭バイト
ID_CRC1_POS                 equ     05h         ; 受信CRCの後続バイト
ID_LENGTH_L_POS             equ     06h         ; 計算済みセクタ長の下位バイト
ID_LENGTH_H_POS             equ     07h         ; 計算済みセクタ長の上位バイト
ID_SIZE                     equ     08h         ; セクタIDリスト1件のバイト数

; sector_status_buffの各要素。用途に合わせて意味を区別する。
SECTOR_STATUS_POS           equ     00h         ; 読取り・照合の結果
SECTOR_DELETED_POS          equ     00h         ; D88書き戻し時の削除データマーク

; 現在位置を指す文字ポインタ。
CHR_POS                     equ     00h         ; 現在の文字

; リトルエンディアンの32ビット値。BYTE0が最下位、BYTE3が最上位。
U32_BYTE0_POS               equ     00h
U32_BYTE1_POS               equ     01h
U32_BYTE2_POS               equ     02h
U32_BYTE3_POS               equ     03h

; リードID時のセクタID格納エリア
; データ書き込み時のバッファ (最大 28b0h)

read_id_list		equ 07000h

;;id_list_buff		equ	08000h

; セクタ読込時の結果格納エリア (32セクタ分)
sector_status_buff			equ	0a000h
sector_status_buff_size		equ		32

; トラックデータ格納エリア
read_track_buff		equ	read_id_list + 0100h
;;track_buff			equ	id_list_buff + 0100h

; トラックデータ収納エリア最大 (12KB)
;;track_buff_max		equ read_id_list + 12*1024

read_track_buff_max		equ	read_id_list + 12*1024


; モニター再転送,再起動時の受取りバッファ
monitor_buff		equ 07000h

; EMM起動時のシステム書込みアドレス (24bit)
emm_boot_adrs		equ	00100h

TRACK_DATA_SIZE		equ	028b0h

END_CODE			equ	'$' 

; レスポンス
RES_OK					equ		00h		; OK
RES_FORMAT_OVER			equ		0ffh	; WriteTrack用データがサイズを超えた
RES_CHECKSUM_ERR		equ		0feh	; チェックサムエラー
RES_INDEX_TIMEOUT           equ     0f9h	; INDEX待ちタイムアウト
RES_ID_OVER                 equ     0fah
RES_READ_OVER			equ		0fdh	; READ DISK時のデータがバッファ(8KB)を超えた
RES_VERIFY_ERR			equ		0fch	; Verityエラー
RES_CONNECTION_ERR		equ		0fbh	; 通信/接続エラー


;---------------------------------------------------------------;
END

