#!/bin/sh
cd "$(dirname "$0")"
if [ -f "./lib.sh" ] ; then
	. "./lib.sh"
else
	echo "lib.sh introuvable, démarrage impossible"
	exit 1
fi


while [ -z "$nom" ]; do
	read -p "Nom de fichier pour la requête (l'extension sera ajoutée automatiquement) : " nom
	e=0
	[ -f "$dir_key/$nom.key" ] && let e++
	[ -f "$dir_req/$nom.csr" ] && let e++
	[ -f "$dir_crt/$nom.crt" ] && let e++
	[ -f "$dir_crt/$nom-chain.pem" ] && let e++
	[ -d "$dir_ca/$nom" ] && let e++
	if [ $e -gt 0 ] ; then
		echo "nom de requête déjà utilisé"
		nom=""
	fi;
done


key_file="$dir_key/$nom.key"
csr_file="$dir_req/$nom.csr"
crt_file="$dir_crt/$nom.crt"


echo "Type de clef ?"
case "$( slct "$EC" "$RSA" )" in 
	"$EC")
		echo "Type de courbe :" ; keyargs=$( slct $(curve_list) )
		[ -n "$keyargs" ] && keyargs="ecparam -genkey -noout -name $keyargs" || exit
	;;
	"$RSA")
		echo "Longueur de clef :" ; keyargs=$( slct $(rsa_length_list) )
		[ -n "$keyargs" ] && keyargs="genrsa $keyargs" || exit
	;;
	*) exit ;;
esac


# Signature algo
sig_alg=$( slct $(hash_alg_list) )
[ -z "$sig_alg" ] && die 2 "No signature algorithm selected"


# la CA signataire ajoute les extensions
# l'important c'est avec ou sans SAN
# pour une selfsign, les extensions doivent être fournies
# on ne fera de l'auto sign que pour une rootCA
printf "\nRequest configuration file :\n"
cfg_file="$dir_cfg/$( slct $( ls -1 "$dir_cfg" 2>/dev/null | egrep "\.conf$" ) )"
[ ! -f "$cfg_file" ] && die 1 "No config file selected"


# recherche des extensions disponibles
ext=$( slct $( seek_ext "$ext_req" "$cfg_file" ) )
[ -z "$ext" ] && die 2 "No extension selected from $cfg_file"


# ajout subjectAltName suivant l'extension demandée
if [ $(echo "$ext" | grep -ic "no_san") -eq 0 ] ; then
	printf "%s\n" "Définition du SAN suivant la forme <type>:<valeur>,<type>:<valeur>,..."
	printf "Eléments :\n\t%s\n\t%s\n\t%s\n\t%s\n\t%s\n\t%s\n\t%s\n" DNS IP URI email RID dirName otherName
	printf "%s\n" "ex : DNS:www.example.com,IP:0.0.0.0"
	while [ -z "$sanc" ]; do
		read sanc
	done
else
	sanc="_"
fi


read -p "Selfsign request ? [y/N] : " ASask

openssl $keyargs >> "$key_file"

if [ "$ASask" == "y" -o "$ASask" == "Y" ] ; then
	while [ -z "$r" ] ; do
		read -p "Temporal certificate validity (min 1 day, ie: 7d | 4w | 6m | 10y ): " c
		r=$( duree "$c" )
	done

	SAN=$sanc openssl req -new -config "$cfg_file" -x509 -extensions "$ext" -key "$key_file" -out "$crt_file" -$sig_alg -days $r

	read -p "Build CA db ? [y/N] " R
	if [ "${R::1}" == "y" ] ;then
		cp -a "$crt_file" "${crt_file%.crt}-chain.pem"
		./make-ca.sh -i "$crt_file"
	fi
else
	SAN=$sanc openssl req -new -config "$cfg_file" -reqexts "$ext" -key "$key_file" -out "$csr_file" -$sig_alg

	read -p "Sign ? [y/N] " R
	[ "${R::1}" = "y" ] && ./signat.sh -i "$csr_file"
fi
