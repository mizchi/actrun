///|
// Helper: parse YAML and lint, return formatted diagnostics
fn lint_yaml(yaml : String) -> String {
  let parsed = @ar.parse_workflow_yaml(yaml)
  match parsed.workflow {
    Option::Some(workflow) => {
      let diags = lint_workflow(workflow)
      if diags.length() == 0 {
        "(no diagnostics)"
      } else {
        let lines : Array[String] = []
        for d in diags {
          lines.push(d.format())
        }
        lines.join("\n")
      }
    }
    Option::None => {
      let lines : Array[String] = []
      for e in parsed.errors {
        lines.push("parse error: " + e)
      }
      lines.join("\n")
    }
  }
}

///|
test "snapshot: undefined context reference" {
  let yaml =
    #|name: test
    #|'on': push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - run: echo "${{ foobar.value }}"
  inspect(
    lint_yaml(yaml),
    content=(
      #|[build/step0] run: error[undefined-context]: undefined context 'foobar'
    ),
  )
}

///|
test "snapshot: unknown function call" {
  let yaml =
    #|name: test
    #|'on': push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - run: echo "${{ myFunc(github.ref) }}"
  inspect(
    lint_yaml(yaml),
    content=(
      #|[build/step0] run: error[unknown-function]: unknown function 'myFunc'
    ),
  )
}

///|
test "snapshot: wrong function arity" {
  let yaml =
    #|name: test
    #|'on': push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - run: |
    #|          echo "${{ contains('one') }}"
    #|          echo "${{ startsWith('a', 'b', 'c') }}"
    #|          echo "${{ success('x') }}"
    #|          echo "${{ hashFiles() }}"
  inspect(
    lint_yaml(yaml),
    content=(
      #|[build/step0] run: error[wrong-arity]: contains() requires 2 arguments, got 1
      #|[build/step0] run: error[wrong-arity]: startsWith() requires 2 arguments, got 3
      #|[build/step0] run: error[wrong-arity]: success() takes no arguments, got 1
      #|[build/step0] run: error[wrong-arity]: hashFiles() requires at least 1 argument
    ),
  )
}

///|
test "snapshot: unknown github property" {
  let yaml =
    #|name: test
    #|'on': push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - run: echo "${{ github.nonexistent_field }}"
  inspect(
    lint_yaml(yaml),
    content=(
      #|[build/step0] run: warning[unknown-property]: unknown property 'nonexistent_field', known: ["event_name", "ref", "ref_name", "sha", "head_ref", "base_ref", "repository", "repository_owner", "actor", "workflow", "run_id", "run_number", "run_attempt", "action", "action_path", "workspace", "server_url", "api_url", "graphql_url", "token", "job", "triggering_actor", "event", "output"]
    ),
  )
}

///|
test "snapshot: unreachable step" {
  let yaml =
    #|name: test
    #|'on': push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - run: echo ok
    #|      - if: 'false'
    #|        run: echo dead
  inspect(
    lint_yaml(yaml),
    content=(
      #|[build/step1] if: warning[unreachable-step]: step is unreachable: condition is always false
    ),
  )
}

///|
test "snapshot: undefined step reference" {
  let yaml =
    #|name: test
    #|'on': push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: setup
    #|        run: echo setup
    #|      - run: echo "${{ steps.missing.outputs.foo }}"
    #|      - run: echo "${{ steps.setup.outputs.ok }}"
  inspect(
    lint_yaml(yaml),
    content=(
      #|[build/step1] run: warning[unknown-property]: unknown property 'missing', known: ["setup"]
      #|[build/step1] expression: error[undefined-step-ref]: reference to undefined step 'missing'
    ),
  )
}

///|
test "snapshot: future step reference" {
  let yaml =
    #|name: test
    #|'on': push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: first
    #|        run: echo "${{ steps.second.outputs.x }}"
    #|      - id: second
    #|        run: echo done
  inspect(
    lint_yaml(yaml),
    content=(
      #|[build/step0] run: warning[unknown-property]: unknown property 'second', known: []
      #|[build/step0] expression: error[future-step-ref]: reference to future step 'second' (defined at index 1, current index 0)
    ),
  )
}

///|
test "snapshot: undefined needs reference" {
  let yaml =
    #|name: test
    #|'on': push
    #|jobs:
    #|  deploy:
    #|    runs-on: ubuntu-latest
    #|    needs: [build, test]
    #|    steps:
    #|      - run: echo deploy
  inspect(
    lint_yaml(yaml),
    content=(
      #|[deploy/step-1] needs: error[undefined-needs]: job 'deploy' depends on undefined job 'build'
      #|[deploy/step-1] needs: error[undefined-needs]: job 'deploy' depends on undefined job 'test'
    ),
  )
}

///|
test "snapshot: circular dependency" {
  let yaml =
    #|name: test
    #|'on': push
    #|jobs:
    #|  a:
    #|    runs-on: ubuntu-latest
    #|    needs: [b]
    #|    steps:
    #|      - run: echo a
    #|  b:
    #|    runs-on: ubuntu-latest
    #|    needs: [c]
    #|    steps:
    #|      - run: echo b
    #|  c:
    #|    runs-on: ubuntu-latest
    #|    needs: [a]
    #|    steps:
    #|      - run: echo c
  inspect(
    lint_yaml(yaml),
    content=(
      #|[a/step-1] needs: error[circular-needs]: circular dependency detected: a -> b -> c -> a
    ),
  )
}

///|
test "snapshot: unused job outputs" {
  let yaml =
    #|name: test
    #|'on': push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    outputs:
    #|      version: ${{ steps.ver.outputs.version }}
    #|    steps:
    #|      - id: ver
    #|        run: echo "version=1.0" >> $GITHUB_OUTPUT
    #|  deploy:
    #|    runs-on: ubuntu-latest
    #|    needs: [build]
    #|    steps:
    #|      - run: echo "deploying without using outputs"
  inspect(
    lint_yaml(yaml),
    content=(
      #|[build/step-1] outputs: warning[unused-outputs]: job 'build' declares outputs but they are not referenced by downstream jobs
    ),
  )
}

///|
test "snapshot: multiple errors in one workflow" {
  let yaml =
    #|name: test
    #|'on': push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - run: echo "${{ badctx.x }}"
    #|      - run: echo "${{ noSuchFn() }}"
    #|      - if: 'false'
    #|        run: echo dead
    #|  broken:
    #|    runs-on: ubuntu-latest
    #|    needs: [missing]
    #|    steps:
    #|      - run: echo "${{ steps.ghost.outputs.y }}"
  inspect(
    lint_yaml(yaml),
    content=(
      #|[build/step0] run: error[undefined-context]: undefined context 'badctx'
      #|[build/step1] run: error[unknown-function]: unknown function 'noSuchFn'
      #|[broken/step0] run: warning[unknown-property]: unknown property 'ghost', known: []
      #|[build/step2] if: warning[unreachable-step]: step is unreachable: condition is always false
      #|[broken/step0] expression: error[undefined-step-ref]: reference to undefined step 'ghost'
      #|[broken/step-1] needs: error[undefined-needs]: job 'broken' depends on undefined job 'missing'
    ),
  )
}

///|
test "snapshot: clean workflow (no errors)" {
  let yaml =
    #|name: test
    #|'on': push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - id: greet
    #|        run: echo "${{ github.actor }}"
    #|      - run: echo "${{ steps.greet.outputs.msg }}"
    #|      - run: echo "${{ contains(github.ref, 'main') }}"
    #|      - if: success()
    #|        run: echo "${{ toJSON(env) }}"
  inspect(
    lint_yaml(yaml),
    content=(
      #|(no diagnostics)
    ),
  )
}

///|
test "snapshot: needs expression type check" {
  let yaml =
    #|name: test
    #|'on': push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - run: echo build
    #|  deploy:
    #|    runs-on: ubuntu-latest
    #|    needs: [build]
    #|    steps:
    #|      - if: needs.build.result == 'success'
    #|        run: echo "${{ needs.build.outputs.version }}"
    #|      - run: echo "${{ needs.unknown_job.result }}"
  inspect(
    lint_yaml(yaml),
    content=(
      #|[deploy/step1] run: warning[unknown-property]: unknown property 'unknown_job', known: ["build"]
    ),
  )
}

///|
test "snapshot: job-level if condition error" {
  let yaml =
    #|name: test
    #|'on': push
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    if: badcontext.value == 'x'
    #|    steps:
    #|      - run: echo build
  inspect(
    lint_yaml(yaml),
    content=(
      #|[build/step-1] if: error[undefined-context]: undefined context 'badcontext'
    ),
  )
}
