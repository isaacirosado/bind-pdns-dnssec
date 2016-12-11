#!/usr/bin/env bash
#See README for details

ACTION="${1}"
if [[ "${ACTION}" != "" ]]; then
  CONTAINER="${2}"
  if [[ "${ACTION}" == "shell" ]]; then
    CONTAINER_ID="${3}"
    if [[ "${CONTAINER_ID}" == "" ]]; then
      CONTAINER_ID="1"
    fi
  fi
else
  ACTION="start"
fi

case "${ACTION}" in
  "build" )
    docker-compose build ${CONTAINER}
    ;;
  "logs" )
    docker-compose logs -f ${CONTAINER}
    ;;
  "rm"|"destroy" )
    docker-compose kill ${CONTAINER}
    docker-compose rm -f -v ${CONTAINER}
    ;;
  "stop" )
    docker-compose stop ${CONTAINER}
    ;;
  "shell" )
    docker-compose exec --index=${CONTAINER_ID} ${CONTAINER} bash
    ;;
  "start" )
    docker-compose up --build -d ${CONTAINER}
    ;;
  "status" )
    docker-compose ps
    ;;
esac

case "${ACTION}" in
  "start" )
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
    if [[ "${CONTAINER}" == "" ]] || [[ "${CONTAINER}" == "tld-server" ]]; then
      echo "" > update-hosts.sh
      docker-compose scale tld-server=2
      if [[ ! -d "tld-server/keys" ]]; then
        mkdir -p tld-server/keys \
        && docker-compose exec tld-server pdnsutil generate-zone-key ksk > tld-server/keys/ksk.txt \
        && docker-compose exec tld-server pdnsutil generate-zone-key zsk > tld-server/keys/zsk1.txt \
        && docker-compose exec tld-server pdnsutil generate-zone-key zsk > tld-server/keys/zsk2.txt
      fi
      ROOTCNT_NAME="`docker-compose ps | awk '{ print $1; }' | grep "root-server_1$"`"
      for index in {1..2}; do
        TLDCNT_NAME="`docker-compose ps | awk '{ print $1; }' | grep "tld-server_${index}$"`"
        TLDCNT_IP="`docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${TLDCNT_NAME}`"
        docker cp tld-server/keys ${TLDCNT_NAME}:/root/keys \
        && docker-compose exec --index=${index} tld-server '/root/init-db.sh' "${index}" "${zone}"
        for zone in tld; do
          docker-compose exec --index=${index} tld-server '/root/init-zone.sh' "${index}" "${zone}"
          DS="`docker-compose exec --index=${index} tld-server pdnsutil show-zone ${zone} | grep -e '^DS' | sed -e "s| *;.*||g" -e "s|.*= *|update add |g" -e "s|\. IN DS|. 86400 IN DS|g"`"
          echo "zone .
            debug
            update delete tld-server${index}. A
            update add tld-server${index}. 86400 IN A ${IP}
            update add ${zone}. 86400 IN NS tld-server${index}.
            ${DS}" > data.txt
          docker cp data.txt ${ROOTCNT_NAME}:/root/ \
          && docker-compose exec root-server '/root/update-dns.sh' '/root/data.txt'
        done
        echo "IP=\$(dig @root-server +short tld-server${index}) && echo \"\${IP} tld-server${index}\" >> /etc/hosts" >> update-hosts.sh
      done
      rm -Rf data.txt
    fi
    if [[ "${CONTAINER}" == "" ]]; then
      for cnt_name in `docker-compose ps | grep "Up" | awk '{ print $1; }'`; do
        docker cp update-hosts.sh ${cnt_name}:/root/ \
        && docker exec -i ${cnt_name} bash /root/update-hosts.sh
      done
      rm -f update-hosts.sh
    fi
    ;;
  "destroy" )
    docker images -q | xargs -IID docker rmi ID
    ;;
esac
