Set-Location 'C:\Users\Vadim\Downloads\bcfinal\Final-BTH2'

git add -u
$staged = git diff --cached --name-only
if ($staged -ne '') {
  git commit -m 'style: format Solidity sources (run forge fmt)'
} else {
  Write-Output 'No staged tracked changes to commit.'
}

git add .github/workflows/ci.yml
$staged = git diff --cached --name-only
if ($staged -ne '') {
  git commit -m 'ci: add GitHub Actions workflow (forge tests, frontend & subgraph build)'
} else {
  Write-Output 'No staged CI changes to commit.'
}

git add README.md
$staged = git diff --cached --name-only
if ($staged -ne '') {
  git commit -m 'docs: add README with local dev & verification instructions'
} else {
  Write-Output 'No staged README changes to commit.'
}

git push -u origin ci/add-workflow-readme
