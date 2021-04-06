package netlify

import (
	"dagger.io/dagger"
	"dagger.io/alpine"
	"dagger.io/dagger/op"
)

// A Netlify account
#Account: {
	// Use this Netlify account name
	// (also referred to as "team" in the Netlify docs)
	name: string | *""

	// Netlify authentication token
	token: dagger.#Secret
}

// A Netlify site
#Site: {
	// Netlify account this site is attached to
	account: #Account

	// Contents of the application to deploy
	contents: dagger.#Artifact

	// Deploy to this Netlify site
	name: string

	// Host the site at this address
	customDomain?: string

	// Create the Netlify site if it doesn't exist?
	create: bool | *true

	// Website url
	url: string

	// Unique Deploy URL
	deployUrl: string

	// Logs URL for this deployment
	logsUrl: string

	#up: [
		op.#Load & {
			from: alpine.#Image & {
				package: bash: "=~5.1"
				package: jq:   "=~1.6"
				package: curl: "=~7.74"
				package: yarn: "=~1.22"
			}
		},
		op.#Exec & {
			args: ["yarn", "global", "add", "netlify-cli@2.47.0"]
		},
		op.#Exec & {
			args: [
				"/bin/bash",
				"--noprofile",
				"--norc",
				"-eo",
				"pipefail",
				"-c",
				code,
			]
			env: {
				NETLIFY_SITE_NAME: name
				if (create) {
					NETLIFY_SITE_CREATE: "1"
				}
				if customDomain != _|_ {
					NETLIFY_DOMAIN: customDomain
				}
				NETLIFY_ACCOUNT:    account.name
				NETLIFY_AUTH_TOKEN: account.token
			}
			dir: "/src"
			mount: "/src": from: contents
		},
		op.#Export & {
			source: "/output.json"
			format: "json"
		},
	]
}

// FIXME: this should be outside
let code = #"""
	create_site() {
	    url="https://api.netlify.com/api/v1/${NETLIFY_ACCOUNT:-}/sites"

	    response=$(curl -s -S -f -H "Authorization: Bearer $NETLIFY_AUTH_TOKEN" \
	                -X POST -H "Content-Type: application/json" \
	                $url \
	                -d "{\"name\": \"${NETLIFY_SITE_NAME}\", \"custom_domain\": \"${NETLIFY_DOMAIN}\"}"
	            )
	    if [ $? -ne 0 ]; then
	        exit 1
	    fi

	    echo $response | jq -r '.site_id'
	}

	site_id=$(curl -s -S -f -H "Authorization: Bearer $NETLIFY_AUTH_TOKEN" \
	            https://api.netlify.com/api/v1/sites\?filter\=all | \
	            jq -r ".[] | select(.name==\"$NETLIFY_SITE_NAME\") | .id" \
	        )
	if [ -z "$site_id" ] ; then
	    if [ "${NETLIFY_SITE_CREATE:-}" != 1 ]; then
	        echo "Site $NETLIFY_SITE_NAME does not exist"
	        exit 1
	    fi
	    site_id=$(create_site)
	    if [ -z "$site_id" ]; then
	        echo "create site failed"
	        exit 1
	    fi
	fi
	netlify deploy \
	    --dir="$(pwd)" \
	    --site="$site_id" \
	    --prod \
	| tee /tmp/stdout

	url=$(</tmp/stdout sed -n -e 's/^Website URL:.*\(https:\/\/.*\)$/\1/p' | tr -d '\n')
	deployUrl=$(</tmp/stdout sed -n -e 's/^Unique Deploy URL:.*\(https:\/\/.*\)$/\1/p' | tr -d '\n')
	logsUrl=$(</tmp/stdout sed -n -e 's/^Logs:.*\(https:\/\/.*\)$/\1/p' | tr -d '\n')

	jq -n \
		--arg url "$url" \
		--arg deployUrl "$deployUrl" \
		--arg logsUrl "$logsUrl" \
		'{url: $url, deployUrl: $deployUrl, logsUrl: $logsUrl}' > /output.json
	"""#
