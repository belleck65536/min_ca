#!/bin/sh
#
# signat.sh -c "config_file" -e "extension" -i "req_file"

. ./lib.sh

function display_help () {
	die "Usage : $(basename $0) <configuration> <extensions> <requete>"
}

while getopts ":c:e:i:" opt; do
	case $opt in
		c) [ -f "$OPTARG" ] && cfg_file="$OPTARG" || die "erreur sur fichier de configuration \"$OPTARG\"" ;;
		i) [ -f "$OPTARG" ] && req_file="$OPTARG" || die "erreur sur fichier de requête \"$OPTARG\"" ;;
		e) exten="$OPTARG" ;;
		\?) echo "Invalid option: -$OPTARG" ; display_help ;;
		:) echo "Option -$OPTARG requires an argument." ; display_help ;;
	esac
done

# validation i
# si pas d'argument fourni, on recherche une CSR
if [ -z "$req_file" ] ; then
	slct  $(
		for csr in $( ls -1 ${dir_req}/*.csr 2>/dev/null ) ; do
			crt_file=$( basename "${csr%.csr}.crt" )
			[ ! -f "$dir_crt/$crt_file" ] && echo "$csr"
		done
	)
fi
# si on a toujours pas d'arguments, c'est qu'il n'y avait rien en entrée et que la sélection n'a rien donné (pas de résultat/tout est signé)
[ -z "$req_file" ] && die "aucune requête disponible pour être signée"

# si le CRT associé existe, on sort car cette vérif a été exécuté lors de la selection des requêtes.
# ce test ne sert que pour l'utilsation avec arguments
[ -f "${req_file%.csr}.crt" ] && die "Nom de certificat signé déjà utilisé \"${req_file%.csr}.crt\""

# validation c
[ -z "$cfg_file" ] && slct $( ls *-ca/*.conf 2>/dev/null )
# choisir config, si liste vide, sortir
[ -z "$cfg_file" ] && die "aucune configuration disponible pour signer la requête"

# validation e
if [ -z "$exten" ] ; then
	exten="$( slct $( grep -e "\s*\[.*_ca\s*\]\s*" "$cfg_file" | sed -r 's/\s*\[\s*//g' | sed -r 's/\s*\]\s*//g' | tr '\n' ' ') )_ca"
fi

[ -z "$exten" ] && die "aucune extension disponible pour signer la requête"

[ $( grep -ec "\s*\[\s*$exten\s*\]\s*" ) -lt 1 ] && die "extension \"$exten\" introuvable dans la configuration \"$cfg_file\""

echo openssl ca -config "$cfg_file" -in "$req_file" -out "${req_file%.csr}.crt" -extensions "$exten" -notext

if [ -f "${req_file%.csr}.key" -a -f "${req_file%.csr}.crt" ]; then
	read -p "Convertir le certificat signé en PKCS#12 ? [y/n] " R
	[ "${R::1}" = "y" ] && openssl pkcs12 -export -inkey "${req_file%.csr}.key" -in "${req_file%.csr}.crt" -out "${req_file%.csr}.p12"
	read -p "Supprimer les fichiers locaux de cette certification ? [y/n] " R
	[ "${R::1}" = "y" ] && rm -f "${req_file%.csr}."*
fi

echo cp "${req_file%.csr}."* /home/cert/
