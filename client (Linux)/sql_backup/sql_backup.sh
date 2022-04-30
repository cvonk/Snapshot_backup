#!/bin/bash
/bin/whoami
set -x
FILESTOKEEP=3
BKBASE=${HOME}/www/coertvonk.com/sql_backup
FNBASE=${BKBASE}/`date +%Y-%m-%d`
mkdir -p ${BKBASE}
echo ${FNBASE}
for ii in wordpress recipes genealogy ; do
    echo "${FNBASE}_${ii}"
    mysqldump --defaults-extra-file=${BKBASE}/.${ii}.cnf cvonk_${ii} | gzip > ${FNBASE}_${ii}.sql.gz
    ls -tr ${BKBASE}/*${ii}.sql.gz | head -n -3 | xargs --no-run-if-empty rm &2>/dev/null
done
