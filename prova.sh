#!/bin/bash
set -e

process_query() {
  if [[ "$REPO_CLONE_DEST"/"$1" == *.sql ]]; then
    if [ -e "$REPO_CLONE_DEST"/"$1" ]; then
      echo "Query file mode" >&2
      sql-formatter -l plsql "$REPO_CLONE_DEST"/"$1" -o "$REPO_CLONE_DEST"/"$1"
      python /platform/sql/scripts/preprocess_sql.py "$REPO_CLONE_DEST"/"$1"
      sql-formatter -l plsql "$REPO_CLONE_DEST"/"$1" -o "$REPO_CLONE_DEST"/"$1"
      sed -i 's/\/[[:space:]]/\/\n/g' "$REPO_CLONE_DEST"/"$1"
      RUN_QUERY="@""$REPO_CLONE_DEST"/"$1"
    else
      echo "Script $1 doesn´t exist" >&2
      exit 3
    fi
  else
    echo "Query string mode" >&2
    if [[ "$1" == *\; ]]; then
      RUN_QUERY="$1"
    else
      echo "Queries should end with semicolon (;)... Adding for execution" >&2
      RUN_QUERY="$1"";"
    fi
  fi
  echo "$RUN_QUERY"
}

# Cloning the provided repo
echo "################"
echo "# Cloning repo #"
echo "################"
mkdir -p "$REPO_CLONE_DEST"
if [ "$MODE" == "remote" ]; then
  sh /platform/scripts/git-config-entrypoint.sh
fi

CONFIG_QUERY=$(process_query "$CONFIG_PATH")
RUN_QUERY=$(process_query "$QUERY")

# Restore vault secrets
USER=$(vault kv get -field=user "$ENGINE/$SECRET")
PASSWORD=$(vault kv get -field=password "$ENGINE/$SECRET")
DSN=$(vault kv get -field=dsn "$ENGINE/$SECRET")

if [ "$OUTPUT_MODE" == "silent" ]; then
  echo "Running $RUN_QUERY in $OUTPUT_MODE mode"
  sqlplus -S "$USER"/"$PASSWORD"@"$DSN" <<EOF
  WHENEVER SQLERROR EXIT SQL.SQLCODE $ERROR_BEHAVIOR
  WHENEVER OSERROR EXIT FAILURE
  SET TERMOUT OFF;
  alter session set NLS_DATE_FORMAT="$DATE_FORMAT";
  $CONFIG_QUERY
  $RUN_QUERY $QUERY_ARGS
EOF
elif [ "$OUTPUT_MODE" == "log" ]; then
  echo "Running $RUN_QUERY in $OUTPUT_MODE mode"
  sqlplus -S -M "CSV ON" "$USER"/"$PASSWORD"@"$DSN" <<EOF
  WHENEVER SQLERROR EXIT SQL.SQLCODE $ERROR_BEHAVIOR
  WHENEVER OSERROR EXIT FAILURE
  alter session set NLS_DATE_FORMAT="$DATE_FORMAT";
  $CONFIG_QUERY
  $RUN_QUERY $QUERY_ARGS
EOF
elif [ "$OUTPUT_MODE" == "file" ]; then
  echo "Running $RUN_QUERY in $OUTPUT_MODE mode"
  sqlplus -S -M "CSV ON" "$USER"/"$PASSWORD"@"$DSN" <<EOF
  WHENEVER SQLERROR EXIT SQL.SQLCODE $ERROR_BEHAVIOR
  WHENEVER OSERROR EXIT FAILURE
  SET TERMOUT OFF;
  SET MARKUP CSV ON DELIMITER "$OUTPUT_COLSEP" QUOTE $OUTPUT_QUOTE;
  SPOOL /tmp/output_tmp.csv;
  SET FEED OFF
  SET VERIFY OFF
  set numwidth 30
  alter session set NLS_DATE_FORMAT="$DATE_FORMAT";
  alter session set nls_numeric_characters="$OUTPUT_NUMSEP";
  $CONFIG_QUERY
  $RUN_QUERY $QUERY_ARGS
  SPOOL OFF;
EOF
  sed -i -e 's/|\./|0\./gm' -e 's/|-\./|-0\./gm' -e 's/^\./0\./gm' -e 's/^-\./-0\./gm' /tmp/output_tmp.csv
  sed -i -e 's/|\,/|0\,/gm' -e 's/|-\,/|-0\,/gm' -e 's/^\,/0\,/gm' -e 's/^-\,/-0\,/gm' /tmp/output_tmp.csv
  sed 1d /tmp/output_tmp.csv >/dag/run/$OUTPUT_FILE_NAME
  rm -rf /tmp/output_tmp.csv
elif [ "$OUTPUT_MODE" == "ata" ]; then
  echo "Running $RUN_QUERY in $OUTPUT_MODE mode"
  sqlplus -S -M "CSV ON" "$USER"/"$PASSWORD"@"$DSN" <<EOF
  WHENEVER SQLERROR EXIT SQL.SQLCODE $ERROR_BEHAVIOR
  WHENEVER OSERROR EXIT FAILURE
  SET TERMOUT OFF;
  SET MARKUP CSV ON DELIMITER "$OUTPUT_COLSEP" QUOTE $OUTPUT_QUOTE;
  SPOOL /tmp/output_tmp.csv;
  SET FEED OFF
  SET VERIFY OFF
  set numwidth 30
  alter session set NLS_DATE_FORMAT="$DATE_FORMAT";
  alter session set nls_numeric_characters="$OUTPUT_NUMSEP";
  $CONFIG_QUERY
  $RUN_QUERY $QUERY_ARGS
  SPOOL OFF;
EOF
  sed -i -e 's/|\./|0\./gm' -e 's/|-\./|-0\./gm' -e 's/^\./0\./gm' -e 's/^-\./-0\./gm' /tmp/output_tmp.csv
  sed -i -e 's/|\,/|0\,/gm' -e 's/|-\,/|-0\,/gm' -e 's/^\,/0\,/gm' -e 's/^-\,/-0\,/gm' /tmp/output_tmp.csv
  sed 1d /tmp/output_tmp.csv >/dag/ata/$OUTPUT_FILE_NAME
  rm -rf /tmp/output_tmp.csv
else
  echo "Unsupported mode $OUTPUT_MODE"
  exit 1
fi