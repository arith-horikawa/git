#!/bin/sh

#シェルのパス
shell_path=/root/shell/

#バックアップ世代数
sedai=2
sedai_day=`date +"%Y%m%d" -d "-$sedai day"`

#エラーコード初期化
error_code=0
end_code=0

#成功失敗メール先
mail_add=xr2000@e-mail.jp

#日付
hiduke=`date +"%Y%m%d"`

#ログ・ファイルの定義
backlog=`date +"%Y%m%d"`_shellbk.log
backmysqllog=`date +"%Y%m%d"`_mysqlbk.log

#バックアップ先のバッファー 10GB
yoryo_buf=10240000

#scpの転送速度のリミット 単位はkbit/s 307200は37.5MByte/s 300Mbps
#scp_limit=307200

#ループ間の休止時間
sleep_time=5

#メール送付用文中に挿入するステータス
status=normal

#空き容量格納
akiyoryo=`df | grep data/mysql | tail -1 | awk '{print $3}'`
akiyoryo_buf=`expr ${akiyoryo} - ${yoryo_buf}`


#バックアップ出力先の初期化 mysql backupは、新規フォルダでないと失敗する
rm -rf /data/mysql_backups/back_dir/*


        if [ -e $1 ]; then
                echo `date +"%Y%m%d%H%M"` ${1} list file check OK >> ${backlog}
        else
                echo `date +"%Y%m%d%H%M"` ${1} list file check NG >> ${backlog}
        fi


for i in `cat $1`
do

        #リストファイルの要素分離
        db_name=`echo $i | awk 'BEGIN{FS = ","}{print $1}'`
        folder_name=`echo $i | awk 'BEGIN{FS = ","}{print $2}'`


        ##バックアップ対象DB容量チェック DBのファイルサイズは、圧縮をかけると半分以下になるので容量の比較は2分の1で実施 する
        useyoryo=`du -s /data/mysql/${folder_name} | awk '{print $1}'`
        useyoryo_comp=`expr ${useyoryo} / 2`

        echo "空き容量" $akiyoryo >> ${backlog}
        echo ${folder_name} $useyoryo >> ${backlog}

        #容量の比較、問題無ければ本処理へ、足りなければ次のループへ
        if [ ${akiyoryo_buf} -lt ${useyoryo_comp} ]; then
                echo `date +"%Y%m%d%H%M"` ${folder_name} "容量オーバーです。バックアッップをスキップします" >> ${backlog}
                continue

        fi


        ##バックアップ　
        /opt/mysql/meb-3.10/bin/mysqlbackup backup --host=localhost --user=arithmetic -parith21332133ktiocfne409 --backup-dir=/data/mysql_backups/back_dir/${folder_name} --include-tables=${db_name} --no-locking  --compress >>${backmysqllog} 2>&1

        error_code=$?


        ##バックアップ結果判定  成功もログに出す

        if [ ${error_code} -ne 0 ]; then
		end_code=1
		status=mysqlbackup_error
                echo `date +"%Y%m%d%H%M"` ${folder_name} mysql backup false >> ${backlog}
		ssh -i /home/mysqlbk/.ssh/id_rsa mysqlbk@ar-13-1-b01-adm-01 "echo mysql backup failed ${status} | Mail -s ${HOSTNAME}_backup_failed ${mail_add}"
                continue
        else
		status=normal
                echo `date +"%Y%m%d%H%M"` ${folder_name} mysql backup success >> ${backlog}
        fi

        #ファイルの転送と世代管理　
        #n日前のバックアップファイルを削除
        ssh -i /home/mysqlbk/.ssh/id_rsa mysqlbk@10.45.18.25  rm -rfv /data/glusterfs/img_vol_01/brick02/data/mysql_bk/${folder_name}_${sedai_day} >>${backlog} 2>&1

        error_code=$?

        if [ ${error_code} -ne 0 ]; then
		end_code=1
		status=gfs_file_delete_error
                echo `date +"%Y%m%d%H%M"` ${folder_name} backup delete false >> ${backlog}
		ssh -i /home/mysqlbk/.ssh/id_rsa mysqlbk@ar-13-1-b01-adm-01 "echo mysql backup failed ${status} | Mail -s ${HOSTNAME}_backup_failed ${mail_add}"

        else
		status=normal
                echo `date +"%Y%m%d%H%M"` ${folder_name} backup delete success >> ${backlog}
        fi





#バックアップで出力したフォルダに実行日の日付を付けてストレージサーバに転送する
#付加した日付は、世代管理に使用する
        scp -r -i /home/mysqlbk/.ssh/id_rsa /data/mysql_backups/back_dir/${folder_name} mysqlbk@10.45.18.25 :/data/glusterfs/img_vol_01/brick02/data/mysql_bk/${folder_name}_${hiduke} >>${backlog} 2>&1


        error_code=$?

        if [ ${error_code} -ne 0 ]; then
       		end_code=1
		status=scp_error_${folder_name}
		
                echo `date +"%Y%m%d%H%M"` ${folder_name} file send false >> ${backlog}
		ssh -i /home/mysqlbk/.ssh/id_rsa mysqlbk@ar-13-1-b01-adm-01 "echo mysql backup failed ${status} | Mail -s ${HOSTNAME}_backup_failed ${mail_add}"

	else
		status=normal
                echo `date +"%Y%m%d%H%M"` ${folder_name} file send success >> ${backlog}

        fi

        #ローカルに出力したバックアップを削除
        rm -rfv /data/mysql_backups/back_dir/${folder_name} >> ${backlog}

        sleep ${sleep_time}

done


#ログファイルの削除
ssh -i /home/mysqlbk/.ssh/id_rsa mysqlbk@10.45.18.25  rm -rfv /data/glusterfs/img_vol_01/brick02/data/mysql_bk/${sedai_day}*log >>${backlog}

#ログファイルの転送
scp -r -l ${scp_limit} -i /home/mysqlbk/.ssh/id_rsa ${shell_path}`date +"%Y%m%d"`*.log mysqlbk@10.45.18.25 :/data/glusterfs/img_vol_01/brick02/data/mysql_bk/

#ローカルのログファイル削除
rm -f ${shell_path}`date +"%Y%m%d"`*.log

if [ ${end_code} -ne 0 ]; then

	ssh -i /home/mysqlbk/.ssh/id_rsa mysqlbk@ar-13-1-b01-adm-01 "echo mysql backup some error | Mail -s ${HOSTNAME}_backup_job_warning_end ${mail_add}"
	
else

	ssh -i /home/mysqlbk/.ssh/id_rsa mysqlbk@ar-13-1-b01-adm-01 "echo mysql backup successful | Mail -s ${HOSTNAME}_backup_job_all_successful ${mail_add}"

fi

exit


