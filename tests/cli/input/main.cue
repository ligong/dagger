package testing

import (
	"dagger.io/dagger/op"
	"dagger.io/dagger"
)

source: dagger.#Artifact
foo:    "bar"

bar: {
	string

	#up: [
		op.#FetchContainer & {ref: "busybox"},
		op.#Exec & {
			args: ["cp", "/source/testfile", "/out"]
			mount: "/source": from: source
		},
		op.#Export & {
			format: "string"
			source: "/out"
		},
	]
}
