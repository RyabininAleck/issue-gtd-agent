#!/usr/bin/env bash
# Создаёт GitHub Project v2, линкует репозиторий, настраивает колонки Status под keys из settings.yml,
# добавляет вид Board, обновляет defaults.repo / defaults.project. Требуются GH_TOKEN (PAT): repo, project, read:org (для org и без предупреждений gh), при необходимости workflow.
set -euo pipefail

GRAPHQL_HDR=(-H "X-Github-Next-Global-ID: 1")

graphql_check_errors() {
  local resp="$1"
  local n
  n="$(echo "${resp}" | jq '.errors // [] | length')"
  if [[ "${n}" != "0" ]]; then
    echo "::error::GraphQL errors: $(echo "${resp}" | jq -c '.errors')" >&2
    echo "${resp}" | jq . >&2
    exit 1
  fi
}

repo_full="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
owner="${repo_full%%/*}"
repo_name="${repo_full#*/}"
settings="${GITHUB_WORKSPACE:-.}/settings.yml"

if [[ ! -f "${settings}" ]]; then
  echo "::error::Файл settings.yml не найден: ${settings}" >&2
  exit 1
fi

existing_repo="$(yq -r '.defaults.repo // 0' "${settings}")"
existing_proj="$(yq -r '.defaults.project // 0' "${settings}")"

if [[ "${existing_repo}" != "0" && "${existing_repo}" != "null" && -n "${existing_repo}" ]] &&
  [[ "${existing_proj}" != "0" && "${existing_proj}" != "null" && -n "${existing_proj}" ]]; then
  echo "Init пропущен: в settings.yml уже заданы defaults.repo=${existing_repo} и defaults.project=${existing_proj}."
  exit 0
fi

echo "gh auth status:"
gh auth status

rest_repo_id="$(gh api "repos/${repo_full}" -q .id)"
echo "REST repo id (numeric): ${rest_repo_id}"

repo_gql="$(
  gh api graphql "${GRAPHQL_HDR[@]}" -f query='
    query($owner: String!, $name: String!) {
      repository(owner: $owner, name: $name) {
        id
        owner {
          id
          login
          __typename
        }
      }
    }
  ' -f "owner=${owner}" -f "name=${repo_name}"
)"
graphql_check_errors "${repo_gql}"
read -r repo_node_id owner_node_id owner_typename owner_login < <(
  echo "${repo_gql}" | jq -r '
    [.data.repository.id,
     .data.repository.owner.id,
     .data.repository.owner.__typename,
     .data.repository.owner.login] | @tsv
  '
)

if [[ -z "${repo_node_id}" || "${repo_node_id}" == "null" ]]; then
  echo "::error::Не удалось получить GraphQL id репозитория" >&2
  exit 1
fi

project_title="${INIT_PROJECT_TITLE:-${repo_name}}"
create_gql="$(
  gh api graphql "${GRAPHQL_HDR[@]}" -f query='
    mutation($ownerId: ID!, $title: String!) {
      createProjectV2(input: { ownerId: $ownerId, title: $title }) {
        projectV2 {
          id
          number
          url
        }
      }
    }
  ' -f "ownerId=${owner_node_id}" -f "title=${project_title}"
)"
graphql_check_errors "${create_gql}"
read -r project_id project_number project_url < <(
  echo "${create_gql}" | jq -r '
    [.data.createProjectV2.projectV2.id,
     (.data.createProjectV2.projectV2.number | tostring),
     .data.createProjectV2.projectV2.url] | @tsv
  '
)

echo "Создан проект #${project_number} (${project_url})"

link_gql="$(
  gh api graphql "${GRAPHQL_HDR[@]}" -f query='
    mutation($projectId: ID!, $repositoryId: ID!) {
      linkProjectV2ToRepository(input: { projectId: $projectId, repositoryId: $repositoryId }) {
        clientMutationId
        repository { id }
      }
    }
  ' -f "projectId=${project_id}" -f "repositoryId=${repo_node_id}"
)"
graphql_check_errors "${link_gql}"

echo "Репозиторий ${repo_full} привязан к проекту."

fields_gql="$(
  gh api graphql "${GRAPHQL_HDR[@]}" -f query='
    query($projectId: ID!) {
      node(id: $projectId) {
        ... on ProjectV2 {
          fields(first: 40) {
            nodes {
              __typename
              ... on ProjectV2SingleSelectField {
                id
                name
              }
            }
          }
        }
      }
    }
  ' -f "projectId=${project_id}"
)"
graphql_check_errors "${fields_gql}"
status_field_id="$(
  echo "${fields_gql}" | jq -r '
    [.data.node.fields.nodes[] | select(.__typename == "ProjectV2SingleSelectField" and .name == "Status") | .id] | first // empty
  '
)"

if [[ -z "${status_field_id}" ]]; then
  echo "::error::Поле Status не найдено в проекте" >&2
  exit 1
fi

status_names=()
while IFS= read -r key; do
  [[ -z "${key}" ]] && continue
  status_names+=("$(python3 -c "import sys; print(' '.join(w.capitalize() for w in sys.argv[1].split()))" "${key}")")
done < <(yq -r '.columns | keys | .[]' "${settings}")

if [[ "${#status_names[@]}" -eq 0 ]]; then
  echo "::error::В settings.yml нет ключей в columns:" >&2
  exit 1
fi

# GitHub теперь требует у каждой опции Status color (enum) и description (non-null string);
# projectId в UpdateProjectV2FieldInput больше не передаётся — достаточно fieldId.
opts_json="$(
  printf '%s\n' "${status_names[@]}" | jq -R -s '
    def colors: ["GRAY","BLUE","GREEN","YELLOW","ORANGE","RED","PINK","PURPLE"];
    split("\n")
    | map(select(length > 0))
    | to_entries
    | map({
        name: .value,
        color: colors[.key % (colors | length)],
        description: ""
      })
  '
)"
vars_json="$(jq -n \
  --arg fieldId "${status_field_id}" \
  --argjson singleSelectOptions "${opts_json}" \
  '{input: {fieldId: $fieldId, singleSelectOptions: $singleSelectOptions}}')"

query_update_field='
  mutation($input: UpdateProjectV2FieldInput!) {
    updateProjectV2Field(input: $input) {
      projectV2Field {
        __typename
        ... on ProjectV2SingleSelectField {
          id
          name
          options {
            name
          }
        }
      }
    }
  }
'

update_gql="$(
  printf '{"query": %s, "variables": %s}\n' \
    "$(jq -Rs . <<<"${query_update_field}")" \
    "${vars_json}" |
    gh api graphql "${GRAPHQL_HDR[@]}" --input -
)"
graphql_check_errors "${update_gql}"

echo "Опции поля Status обновлены (${#status_names[@]} колонок)."

# REST для видов Project v2 согласован с версией API; для user-owned projects GitHub иногда отвечает 404
# даже при валидном project_number — тогда доску нужно добавить вручную в UI.
GH_VIEWS_HDR=(
  -H "Accept: application/vnd.github+json"
  -H "X-GitHub-Api-Version: 2026-03-10"
)

if [[ "${owner_typename}" == "Organization" ]]; then
  views_path="orgs/${owner_login}/projectsV2/${project_number}/views"
else
  views_path="users/${owner_login}/projectsV2/${project_number}/views"
fi

board_ok=0
if gh api --method POST "${GH_VIEWS_HDR[@]}" "/${views_path}" -f name='Board' -f layout='board' >/dev/null 2>&1; then
  board_ok=1
elif [[ "${owner_typename}" != "Organization" ]]; then
  owner_numeric_id="$(gh api "users/${owner_login}" -q .id 2>/dev/null)" || owner_numeric_id=""
  if [[ -n "${owner_numeric_id}" ]]; then
    views_path="users/${owner_numeric_id}/projectsV2/${project_number}/views"
    if gh api --method POST "${GH_VIEWS_HDR[@]}" "/${views_path}" -f name='Board' -f layout='board' >/dev/null 2>&1; then
      board_ok=1
    fi
  fi
fi

if [[ "${board_ok}" -eq 1 ]]; then
  echo "Создан вид Board."
else
  echo "::warning::Не удалось создать вид Board через REST (часто 404 для user-owned Project v2). Добавьте вид Board вручную: ${project_url}" >&2
fi

yq -i ".defaults.repo = ${rest_repo_id}" "${settings}"
yq -i ".defaults.project = ${project_number}" "${settings}"

echo "Обновлён settings.yml: defaults.repo=${rest_repo_id}, defaults.project=${project_number}"
echo "Открыть проект: ${project_url}"
