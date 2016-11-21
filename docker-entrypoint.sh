#!/bin/bash
#set -e

export JAVA_HOME=$(readlink -f $(dirname $(readlink -f $(which java)))/..)
export JAVA_OPTS1="-server"
export JAVA_OPTS2="-Xms256m -Xmx512m"
export JAVA_RUN="${JAVA_HOME}/bin/java"

export PATH=${JAVA_HOME}/bin:$PATH

export CONFDIR=${CONFDIR:-/etc/waarp/conf.d/$WAARP_APPNAME}
export PIDFILE=/var/lib/waarp/${WAARP_APPNAME}/gwftp.pid

export LOGSERVER=" -Dlogback.configurationFile=${CONFDIR}/logback-gwftp.xml "
export LOGCLIENT=" -Dlogback.configurationFile=${CONFDIR}/logback-client.xml "

export JAVARUNCLIENT="${JAVA_RUN} ${JAVA_OPTS2} -cp ${GWFTP_CLASSPATH} ${LOGCLIENT} "
export JAVARUNSERVER="${JAVA_RUN} ${JAVA_OPTS1} ${JAVA_OPTS2} -cp ${GWFTP_CLASSPATH} ${LOGSERVER} "

# Initializing Command Line Tools.
# The script contains command line tools
# to interact with Waarp engine.
# e.g initialize database, submit/list transfer requests.
# --------------------------------------------------
echo $(date --rfc-3339=seconds) 'Initializing Waarp command line tools'

. /usr/share/waarp/init-commands.sh

mkdir -p "/etc/waarp/conf.d/${WAARP_APPNAME}"
cp -vn /etc/waarp/conf.d/template/*.xml /etc/waarp/conf.d/${WAARP_APPNAME}/


# Deploying XML configuration files.
# Copy the configuration from Template,
# if not already customized
# --------------------------------------------------
echo $(date --rfc-3339=seconds) 'Deploying XML configuration files if required'

if [ ! -f ${SERVER_CONFIG} ]; then
    mkdir -p "/etc/waarp/conf.d/${WAARP_APPNAME}"
    cp -vn /etc/waarp/conf.d/template/*.xml /etc/waarp/conf.d/${WAARP_APPNAME}/
fi

# Initializing Directories.
# --------------------------------------------------
echo $(date --rfc-3339=seconds) 'Initializing Directories.'

mkdir /var/lib/waarp/${WAARP_APPNAME}

xmlstarlet ed -P -S -L \
-u "/config/directory/serverhome" -v "/var/lib/waarp/${WAARP_APPNAME}" \
${SERVER_CONFIG}

# Initializing Waarp Password file.
# Update password if key already exists.
# --------------------------------------------------
if [ ! -f "/etc/waarp/certs/${WAARP_APPNAME}-admin-passwd.ggp" ]; then
    echo $(date --rfc-3339=seconds) 'Initializing Waarp password file'
    WAARP_CRYPTED_PASSWORD=$(
        java -cp "${R66_CLASSPATH}" org.waarp.uip.WaarpPassword -pwd "${WAARP_ADMIN_PASSWORD}" \
        -des -ko "/etc/waarp/certs/cryptokey.des" \
        -po "/etc/waarp/certs/${WAARP_APPNAME}-admin-passwd.ggp" 2>&1 | \
        grep "CryptedPwd:" | sed 's#CryptedPwd\:\s##g' \
    )
else
    echo $(date --rfc-3339=seconds) 'Updating Waarp password file'
    WAARP_CRYPTED_PASSWORD=$(
        java -cp "${R66_CLASSPATH}" org.waarp.uip.WaarpPassword -pwd "${WAARP_ADMIN_PASSWORD}" \
        -des -ki "/etc/waarp/certs/cryptokey.des" \
        -po "/etc/waarp/certs/${WAARP_APPNAME}-admin-passwd.ggp" 2>&1 | \
        grep "CryptedPwd:" | sed 's#CryptedPwd\:\s##g' \
    )
fi

xmlstarlet ed -P -S -L \
-u "/config/identity/hostid" -v "${WAARP_APPNAME}" \
-u "/config/identity/sslhostid" -v "${WAARP_APPNAME}-ssl" \
-u "/config/identity/cryptokey" -v "/etc/waarp/certs/cryptokey.des" \
-u "/config/identity/authentfile" -v "/etc/waarp/conf.d/${WAARP_APPNAME}/${WAARP_APPNAME}_Authentication.xml" \
-u "/config/server/serverpasswd" -v "${WAARP_CRYPTED_PASSWORD}" \
${SERVER_CONFIG}

# Initializing Waarp SSL
# --------------------------------------------------
echo $(date --rfc-3339=seconds) 'Initializing Waarp SSL'

# Admin
if [ ! -f "/etc/waarp/certs/${WAARP_APPNAME}_admkey.jks" ]; then
    echo $(date --rfc-3339=seconds) "Generating admin key"
    
    keytool -noprompt -genkey -keysize ${WAARP_KEYSIZE} -keyalg ${WAARP_KEYALG} \
    -sigalg ${WAARP_SIGALG} -validity "${WAARP_KEYVAL}" \
    -alias "${WAARP_APPNAME}_admkey" \
    -dname "${WAARP_SSL_DNAME}" \
    -keystore "/etc/waarp/certs/${WAARP_APPNAME}_admkey.jks" \
    -storepass "${WAARP_ADMKEYSTOREPASS}" \
    -keypass "${WAARP_ADMKEYPASS}"

    xmlstarlet ed -P -S -L \
    -u "/config/server/admkeypath" -v "/etc/waarp/certs/${WAARP_APPNAME}_admkey.jks" \
    -u "/config/server/admkeystorepass" -v ${WAARP_ADMKEYSTOREPASS}  \
    -u "/config/server/admkeypass" -v ${WAARP_ADMKEYPASS} \
    ${SERVER_CONFIG}
fi

# Server
if [ ! -f "/etc/waarp/certs/${WAARP_APPNAME}_server.jks" ]; then
    echo $(date --rfc-3339=seconds) "Generating server key"
    
    keytool -noprompt -genkey -keysize ${WAARP_KEYSIZE} -keyalg ${WAARP_KEYALG} \
    -sigalg ${WAARP_SIGALG} -validity "${WAARP_KEYVAL}" \
    -alias "${WAARP_APPNAME}_server" \
    -dname "${WAARP_SSL_DNAME}" \
    -keystore "/etc/waarp/certs/${WAARP_APPNAME}_gwftp.jks" \
    -storepass "${WAARP_KEYSTOREPASS}" \
    -keypass "${WAARP_KEYPASS}"

    xmlstarlet ed -P -S -L \
    -u "/config/ssl/keypath" -v "/etc/waarp/certs/${WAARP_APPNAME}_gwftp.jks" \
    -u "/config/ssl/keystorepass" -v ${WAARP_KEYSTOREPASS}  \
    -u "/config/ssl/keypass" -v ${WAARP_KEYPASS} \
    ${SERVER_CONFIG}
fi

# Trust
if [ ! -f "/etc/waarp/certs/${WAARP_APPNAME}_trust.jks" ]; then
    echo $(date --rfc-3339=seconds) "Generating trust key"
    
    keytool -noprompt -genkey -keysize ${WAARP_KEYSIZE} -keyalg ${WAARP_KEYALG} \
    -sigalg ${WAARP_SIGALG} -validity "${WAARP_KEYVAL}" \
    -alias "${WAARP_APPNAME}_trust" \
    -dname "${WAARP_SSL_DNAME}" \
    -keystore "/etc/waarp/certs/${WAARP_APPNAME}_trust.jks" \
    -storepass "${WAARP_TRUSTKEYSTOREPASS}"  \
    -keypass "${WAARP_TRUSTKEYSTOREPASS}"

    xmlstarlet ed -P -S -L \
    -u "/config/ssl/trustkeypath" -v "/etc/waarp/certs/${WAARP_APPNAME}_trust.jks" \
    -u "/config/ssl/trustkeystorepass" -v ${WAARP_TRUSTKEYSTOREPASS} \
    ${SERVER_CONFIG}
fi


# Initializing Waarp SNMP file
# --------------------------------------------------
echo $(date --rfc-3339=seconds) 'Initializing Waarp SNMP file'

xmlstarlet ed -P -S -L \
-u "/config/server/snmpconfig" -v "/etc/waarp/conf.d/${WAARP_APPNAME}/snmpconfig.xml" \
${SERVER_CONFIG}

xmlstarlet ed -P -S -L \
-u "/snmpconfig/securities/security/securityauthpass" -v ${WAARP_SNMP_AUTHPASS} \
-u "/snmpconfig/securities/security/securityprivpass" -v ${WAARP_SNMP_PRIVPASS} \
/etc/waarp/conf.d/${WAARP_APPNAME}/snmpconfig.xml


# Initializing Waarp SNMP file
# --------------------------------------------------
echo $(date --rfc-3339=seconds) 'Initializing Waarp authentication XML file'

WAARP_CRYPTED_PASSWORD=$(
    java -cp "${GWFTP_CLASSPATH}" org.waarp.uip.WaarpPassword -pwd "${WAARP_FTPCLIENT_PASSWORD}" \
    -des -ki "/etc/waarp/certs/gwftp-cryptokey.des" \
    -po "/etc/waarp/certs/ftp-client-passwd.ggp" 2>&1 | \
    grep "CryptedPwd:" | sed 's#CryptedPwd\:\s##g' \
)

if [ ! -f "/etc/waarp/conf.d/${WAARP_APPNAME}/${WAARP_APPNAME}_Authentication.xml" ]; then
    echo '<?xml version="1.0" encoding="UTF-8"?><authent xmlns:x0="http://www.w3.org/2001/XMLSchema"></authent>' | xmlstarlet ed \
    -s "/authent" -t elem -n entry -v "" \
    -s "/authent/entry" -t elem -n user -v "${WAARP_FTPCLIENT_USER}" \
    -s "/authent/entry" -t elem -n passwd -v "${WAARP_CRYPTED_PASSWORD}" \
    -s "/authent/entry" -t elem -n account -v "toFTP" \
    -s "/authent/entry" -t elem -n account -v "fromFTP" \
    -s "/authent/entry" -t elem -n admin -v "false" \
    -s "/authent/entry" -t elem -n retreivecmd -v "${WAARP_FTPCLIENT_RETREIVECMD}" \
    -s "/authent/entry" -t elem -n storecmd -v "${WAARP_FTPCLIENT_STORECMD}" \
    -s "/authent/entry" -t elem -n storedelay -v "30000" \
    > /etc/waarp/conf.d/${WAARP_APPNAME}/${WAARP_APPNAME}_Authentication.xml
fi

# Initializing Waarp Database
# --------------------------------------------------
echo $(date --rfc-3339=seconds) 'Initializing Waarp Database'
if [ -z ${MYSQL_ENV_GOSU_VERSION} ]; then
    echo $(date --rfc-3339=seconds) "Database engine is not MySQL/MariaDB"
else
    echo $(date --rfc-3339=seconds) "Database engine is MySQL/MariaDB"
    
    WAARP_DATABASE_TYPE='mysql'
    WAARP_DATABASE_USER:=${MYSQL_ENV_MYSQL_USER:-root}

    if [ "$WAARP_DATABASE_USER" = 'root' ]; then
        WAARP_DATABASE_PASSWORD:=$MYSQL_ENV_MYSQL_ROOT_PASSWORD
    fi
    
    WAARP_DATABASE_PASSWORD=$MYSQL_ENV_MYSQL_PASSWORD
    WAARP_DATABASE_NAME=${MYSQL_ENV_MYSQL_DATABASE:-waarp}
    WAARP_DATABASE_URL="jdbc:mysql://mysql:3306/$WAARP_DATABASE_NAME"

    if [ -z "$WAARP_DATABASE_PASSWORD" ]; then
        echo >&2 'error: missing required WAARP_DATABASE_PASSWORD environment variable'
        echo >&2 '  Did you forget to -e WAARP_DATABASE_PASSWORD=... ?'
        echo >&2
        echo >&2 '  (Also of interest might be WAARP_DATABASE_USER and WAARP_DATABASE_NAME.)'
        exit 1
    fi
fi

if [ -z ${POSTGRES_ENV_GOSU_VERSION} ]; then
    echo $(date --rfc-3339=seconds) "Database engine is not PostgreSQL"
else
    echo $(date --rfc-3339=seconds) "Database engine is PostgreSQL"
   
    WAARP_DATABASE_TYPE='postgresql'
    WAARP_DATABASE_USER:=${POSTGRES_ENV_POSTGRES_USER:-root}

    if [ "$WAARP_DATABASE_USER" = 'postgres' ]; then
        WAARP_DATABASE_PASSWORD:='postgres'
    fi
    
    WAARP_DATABASE_PASSWORD=$POSTGRES_ENV_POSTGRES_PASSWORD
    WAARP_DATABASE_NAME=${POSTGRES_ENV_POSTGRES_DB:-waarp}
    WAARP_DATABASE_URL="jdbc:postgresql://postgres:5432/$WAARP_DATABASE_NAME"

    if [ -z "$WAARP_DATABASE_PASSWORD" ]; then
        echo >&2 'error: missing required WAARP_DATABASE_PASSWORD environment variable'
        echo >&2 '  Did you forget to -e WAARP_DATABASE_PASSWORD=... ?'
        echo >&2
        echo >&2 '  (Also of interest might be WAARP_DATABASE_USER and WAARP_DATABASE_NAME.)'
        exit 1
    fi
fi

xmlstarlet ed -P -S -L \
-u "/config/db/dbdriver" -v "${WAARP_DATABASE_TYPE}" \
-u "/config/db/dbserver" -v "${WAARP_DATABASE_URL}"  \
-u "/config/db/dbuser" -v "${WAARP_DATABASE_USER}" \
-u "/config/db/dbpasswd" -v "${WAARP_DATABASE_PASSWORD}" \
${SERVER_CONFIG}


${GWFTPINIT} -initdb
# ${GWFTPINIT} -auth /etc/waarp/conf.d/${WAARP_APPNAME}/${WAARP_APPNAME}_Authentication.xml
${GWFTPINIT} -upgradedb

echo $(date --rfc-3339=seconds) --------------------------------------------------
echo $(date --rfc-3339=seconds) 'Waarp init process complete; ready for start up.'
echo $(date --rfc-3339=seconds) --------------------------------------------------

/usr/bin/supervisord -c /etc/supervisord.conf -n