#!/bin/bash
# certconvert - Convert certificates and extract keys (.cer, .crt, .pem, .der, .pfx)

set -e

usage() {
  echo "Usage: $0 -i <input_file> -o <output_file|basename> [-p <password>]"
  echo ""
  echo "Examples:"
  echo "  $0 -i cert.cer -o cert.pem"
  echo "  $0 -i cert.pfx -o cert.pem"
  echo "  $0 -i cert.pfx -o cert.key"
  echo "  $0 -i cert.pfx -o cert             # Extracts cert.key, cert.pem, cert-ca.pem"
  echo "  $0 -i cert.pem -o cert.pfx -p secret"
  exit 1
}

# Check if openssl is installed
if ! command -v openssl &>/dev/null; then
  echo "❌ Error: openssl is not installed or not in PATH."
  exit 127
fi

while getopts "i:o:p:" opt; do
  case $opt in
    i) input="$OPTARG" ;;
    o) output="$OPTARG" ;;
    p) password="$OPTARG" ;;
    *) usage ;;
  esac
done

[ -z "$input" ] || [ -z "$output" ] && usage

input_ext="${input##*.}"
output_ext="${output##*.}"
output_base="${output%.*}"

# Determine if output is a basename (no extension)
is_basename_output=false
if [[ "$output" != *.* ]] || [[ "$output_ext" == "$output" ]]; then
  is_basename_output=true
fi

echo "🔄 Converting from .$input_ext..."

# Prepare password flag if provided
pw_flag=""
if [[ -n "$password" ]]; then
  pw_flag="-passin pass:$password"
  export P12_PW="$password"
fi

show_cert_info() {
  local file="$1"
  if [[ -f "$file" ]]; then
    echo ""
    echo "🔎 Certificate info for: $file"
    openssl x509 -noout -fingerprint -sha256 -in "$file"
    openssl x509 -noout -subject -issuer -startdate -enddate -in "$file"
    echo ""
  fi
}

case "${input_ext,,}" in
  cer|der)
    if [[ "$output_ext" == "pem" ]]; then
      openssl x509 -inform der -in "$input" -out "$output"
      show_cert_info "$output"
    else
      echo "❌ Only .pem output is supported for .cer/.der input."
      exit 2
    fi
    ;;
  pem)
    if [[ "$output_ext" == "der" ]]; then
      openssl x509 -outform der -in "$input" -out "$output"
    elif [[ "$output_ext" == "pfx" ]]; then
      echo "🔐 Exporting to .pfx..."
      openssl pkcs12 -export -out "$output" -in "$input" ${pw_flag}
    else
      echo "❌ Only .der or .pfx output is supported for .pem input."
      exit 2
    fi
    ;;
  crt)
    if [[ "$output_ext" == "pem" ]]; then
      cp "$input" "$output"
      echo "ℹ️  .crt and .pem are often the same format."
      show_cert_info "$output"
    else
      echo "❌ Only .pem output is supported for .crt input."
      exit 2
    fi
    ;;
  pfx)
    echo "🔐 Loading .pfx..."
    if [[ "$is_basename_output" == true ]]; then
      openssl pkcs12 -in "$input" -nocerts -nodes $pw_flag -out "${output}.key"
      openssl pkcs12 -in "$input" -clcerts -nokeys $pw_flag -out "${output}.pem"
      openssl pkcs12 -in "$input" -cacerts -nokeys $pw_flag -out "${output}-ca.pem"
      echo "✅ Extracted:"
      echo "- Private key: ${output}.key"
      echo "- Certificate: ${output}.pem"
      echo "- CA chain:    ${output}-ca.pem"
      show_cert_info "${output}.pem"
    elif [[ "$output_ext" == "pem" ]]; then
      openssl pkcs12 -in "$input" -clcerts -nokeys $pw_flag -out "$output"
      show_cert_info "$output"
    elif [[ "$output_ext" == "key" ]]; then
      openssl pkcs12 -in "$input" -nocerts -nodes $pw_flag -out "$output"
    else
      echo "❌ Only .pem, .key or basename output is supported for .pfx input."
      exit 2
    fi
    ;;
  *)
    echo "❌ Unknown input format: .$input_ext"
    exit 2
    ;;
esac

[[ "$is_basename_output" == false ]] && echo "✅ Conversion completed: $output"
