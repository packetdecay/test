#!/bin/bash
# certconvert - Convert and extract certificates and keys (.cer, .crt, .pem, .der, .pfx)

set -e

verbose=false
force=false

usage() {
  echo "Usage: $0 -i <input_file> -o <output_file|basename> [-p <password>] [-f] [-v]"
  echo ""
  echo "Options:"
  echo "  -i <file>     Input certificate (pfx, pem, cer, crt, der)"
  echo "  -o <name>     Output file or basename"
  echo "  -p <pass>     Optional password (for .pfx/.p12)"
  echo "  -f            Force overwrite of output files"
  echo "  -v            Verbose output"
  echo ""
  echo "Examples:"
  echo "  $0 -i cert.pfx -o cert             # Outputs cert.pem, cert.key, cert.crt, cert-ca.pem"
  echo "  $0 -i cert.pem -o cert.pfx -p pass"
  exit 1
}

command -v openssl &>/dev/null || {
  echo "❌ Error: openssl is not installed."
  exit 127
}

while getopts "i:o:p:fv" opt; do
  case $opt in
    i) input="$OPTARG" ;;
    o) output="$OPTARG" ;;
    p) password="$OPTARG" ;;
    f) force=true ;;
    v) verbose=true ;;
    *) usage ;;
  esac
done

[[ -z "$input" || -z "$output" ]] && usage

input_ext="${input##*.}"
output_ext="${output##*.}"
output_base="${output%.*}"

[[ "$output" != *.* || "$output_ext" == "$output" ]] && is_basename_output=true || is_basename_output=false

$verbose && echo "🔄 Input: $input ($input_ext)"
$verbose && echo "➡️  Output: $output"
$verbose && echo "🔐 Password: ${password:+<provided>}"

pw_flag=()
[[ -n "$password" ]] && pw_flag=(-passin "pass:$password")

log() {
  $verbose && echo "📝 $1"
}

show_cert_info() {
  local file="$1"
  [[ -f "$file" ]] || return
  echo ""
  echo "🔎 Certificate info: $file"
  openssl x509 -noout -fingerprint -sha256 -in "$file"
  openssl x509 -noout -subject -issuer -startdate -enddate -in "$file"
  echo ""
}

check_overwrite() {
  local file="$1"
  if [[ -f "$file" && "$force" != true ]]; then
    echo "⚠️  $file exists. Use -f to overwrite."
    return 1
  fi
  return 0
}

copy_pem_to_crt() {
  local pem="$1"
  local crt="${pem%.pem}.crt"
  [[ -f "$crt" && "$force" != true ]] && return
  cp "$pem" "$crt"
  log "Created .crt copy: $crt"
}

case "${input_ext,,}" in
  cer|der)
    [[ "$output_ext" =~ ^(pem|crt)$ ]] || { echo "❌ .cer/.der → .pem or .crt only"; exit 2; }
    check_overwrite "$output" || exit 3
    openssl x509 -inform der -in "$input" -out "$output"
    [[ "$output_ext" == "pem" ]] && copy_pem_to_crt "$output"
    show_cert_info "$output"
    ;;
  pem)
    case "$output_ext" in
      der)
        check_overwrite "$output" || exit 3
        openssl x509 -outform der -in "$input" -out "$output"
        ;;
      crt)
        check_overwrite "$output" || exit 3
        cp "$input" "$output"
        ;;
      pfx)
        check_overwrite "$output" || exit 3
        openssl pkcs12 -export -out "$output" -in "$input" "${pw_flag[@]}"
        ;;
      *)
        echo "❌ .pem → .crt, .der, .pfx only"; exit 2
        ;;
    esac
    ;;
  crt)
    [[ "$output_ext" == "pem" ]] || { echo "❌ .crt → .pem only"; exit 2; }
    check_overwrite "$output" || exit 3
    cp "$input" "$output"
    ;;
  pfx|p12)
    if [[ "$is_basename_output" == true ]]; then
      key="${output}.key"
      pem="${output}.pem"
      crt="${output}.crt"
      ca="${output}-ca.pem"
      for f in "$key" "$pem" "$ca"; do check_overwrite "$f" || exit 3; done

      openssl pkcs12 -in "$input" -nocerts -nodes "${pw_flag[@]}" -out "$key"
      openssl pkcs12 -in "$input" -clcerts -nokeys "${pw_flag[@]}" -out "$pem"
      openssl pkcs12 -in "$input" -cacerts -nokeys "${pw_flag[@]}" -out "$ca"
      copy_pem_to_crt "$pem"

      echo "✅ Extracted:"
      echo "- $key"
      echo "- $pem"
      echo "- $crt"
      echo "- $ca"

      show_cert_info "$pem"
    else
      case "$output_ext" in
        pem|crt)
          check_overwrite "$output" || exit 3
          openssl pkcs12 -in "$input" -clcerts -nokeys "${pw_flag[@]}" -out "$output"
          [[ "$output_ext" == "pem" ]] && copy_pem_to_crt "$output"
          show_cert_info "$output"
          ;;
        key)
          check_overwrite "$output" || exit 3
          openssl pkcs12 -in "$input" -nocerts -nodes "${pw_flag[@]}" -out "$output"
          ;;
        *)
          echo "❌ .pfx → .pem, .crt, .key or basename only"; exit 2
          ;;
      esac
    fi
    ;;
  *)
    echo "❌ Unsupported input format: .$input_ext"
    exit 2
    ;;
esac

[[ "$is_basename_output" == false ]] && echo "✅ Done: $output"
