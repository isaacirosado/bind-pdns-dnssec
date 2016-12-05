#!/usr/bin/env bash
#See README for details

ACTION="${1}"
if [[ "${ACTION}" != "" ]]; then
  CONTAINER="${2}"
else
  ACTION="build"
fi

case "${ACTION}" in
  "prepare" | "build" )
    docker-compose build ${CONTAINER}
    ;;
  "rm"|"destroy" )
    docker-compose kill ${CONTAINER}
    docker-compose rm -f ${CONTAINER}
    ;;
  "stop" )
    docker-compose stop ${CONTAINER}
    ;;
  "status" )
    docker-compose ps
    ;;
esac

case "${ACTION}" in
  "build" | "start" )
    docker-compose up --build -d ${CONTAINER}
    if [[ "${CONTAINER}" == "" ]] || [[ "${CONTAINER}" == "root-server" ]]; then
      CNT_NAME="`docker-compose ps | awk '{ print $1; }' | grep "root-server_1$"`"
      IP="`docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${CNT_NAME}`"
      let "SERIAL = ${SERIAL} + 1"
      echo "zone .
        debug
        update delete root-server. A
        update add root-server. 86400 IN A ${IP}
        update delete . NS root-server.
        update add . 86400 IN NS root-server.
        update delete localhost. A
        update delete . NS localhost" > data.txt
      docker cp data.txt ${CNT_NAME}:/root/ \
      && docker-compose exec root-server '/root/update-dns.sh' '/root/data.txt' \
      && docker-compose exec root-server '/root/sign-zone.sh' '.'
    fi
    if [[ "${CONTAINER}" == "" ]] || [[ "${CONTAINER}" == "mariadb" ]]; then
      docker-compose exec mariadb '/root/init.sh'
    fi
    if [[ "${CONTAINER}" == "" ]] || [[ "${CONTAINER}" == "tld-server" ]]; then
      docker-compose exec tld-server '/root/init-zone.sh' 'tld'
      DS="`docker-compose exec tld-server 'pdnsutil' 'show-zone' 'tld' | grep -e '^DS' | sed -e "s| *;.*||g" -e "s|.*= *|update add |g" -e "s|\. IN DS|. 86400 IN DS|g"`"
      CNT_NAME="`docker-compose ps | awk '{ print $1; }' | grep "tld-server_1$"`"
      IP="`docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${CNT_NAME}`"
      echo "zone .
        debug
        update delete tld-server. A
        update add tld-server. 86400 IN A ${IP}
        update delete tld. NS
        update add tld. 86400 IN NS tld-server.
        ${DS}" > data.txt
      CNT_NAME="`docker-compose ps | awk '{ print $1; }' | grep "root-server_1$"`"
      docker cp data.txt ${CNT_NAME}:/root/ \
      && docker-compose exec root-server '/root/update-dns.sh' '/root/data.txt'
    fi
    ;;
  "destroy" )
    docker images -q | xargs -IID docker rmi ID
    ;;
  "logs" )
    docker-compose logs -f ${CONTAINER}
    ;;
  "shell" )
    docker-compose exec ${CONTAINER} bash
    ;;
esac
