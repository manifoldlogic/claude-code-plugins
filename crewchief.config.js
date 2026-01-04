export default {
  repository: {
    maproomBinaryPath: "/usr/local/share/nvm/versions/node/v20.19.6/lib/node_modules/@crewchief/cli/bin/linux-arm64/crewchief-maproom",
    mainBranch: "main",
    worktreeBasePath: '/workspace/repos/claude-code-plugins'
  },
  worktree: {
    copyIgnoredFiles: [
      ".claude/settings.json",
      ".claude/settings.local.json",
      "crewchief.config.js",
      "crewchief.config.local.js"
    ],
    copyFromPath: '.',
    overwriteStrategy: 'skip'
  },
  launch: {
    askToUpdateLlmGuides: false
  },
  terminal: {
    backend: 'iterm',
    iterm: {
      sessionName: 'crewchief'
    }
  },
  evaluation: {
    autoMergeThreshold: 0.95,
    requireTestsPass: true,
    requireReview: false
  }
};
