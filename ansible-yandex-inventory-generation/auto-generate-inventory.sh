#!/bin/bash
print_log() {
  echo -e "$(date +"%H:%M:%S") $1"
}

yc_cloud_id=""
folder_prefix="auto_"
out_folder="src/auto_hosts"
for folder_id in $(yc resource-manager folder list --cloud-id="${yc_cloud_id}" --format="json" | jq -r '.[].id'); do
  folder_name=$(yc resource-manager folder get --id=$folder_id --format=json | jq -r '.name')
  folder_name_fixed=$(echo $folder_name | tr - _)
  print_log "=> [\"${folder_name}\"] Ищем cloud compute instances в folder: \"${folder_name}\" (folder_id: \"${folder_id}\")\n---"
  # Создаем только если есть хоть одна машина в compute cloud
  if [[ $(yc compute instance list --folder-id=$folder_id --format=json | wc -l) -gt 2 ]]; then
    rm -f $out_folder/$folder_name_fixed && echo "[$folder_name_fixed]" > $out_folder/$folder_prefix$folder_name_fixed
    counter=0
    for compute_id in $(yc compute instance list --folder-id=$folder_id --format=json | jq -r '.[].id'); do
      compute_name=$(yc compute instance get --format=json --id=${compute_id} | jq -r '.name')
      compute_ip=$(yc compute instance get --format=json --id=${compute_id} | jq -r '.network_interfaces[0].primary_v4_address.address')
      echo "$compute_ip" >> $out_folder/$folder_prefix$folder_name_fixed
      printf "%8s Instance: %-40s с адресом: %-15s добавлен в inventory folder: %-15s\n" $(date +"%H:%M:%S") ${compute_name} ${compute_ip} ${out_folder}/${folder_prefix}${folder_name_fixed}
      let counter++
    done
    echo ">> Закончена генерация файла ${out_folder}/${folder_prefix}${folder_name_fixed} <<"
    print_log "В inventory folder: \"${out_folder}/${folder_prefix}${folder_name_fixed}\" добавлено: ${counter} instances\n---\n"
  else
    print_log "В папке \"${folder_name_fixed}\" (folder_id: \"${folder_id}\" отсутствуют инстансы в Compute Cloud. Пропускаем.\n---\n"
  fi
done