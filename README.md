## bolu.dev

Github pages personal blog powered by Jekyll.

### Local Development

Start local development server

#### On Linux (WSL/Ubuntu)
```bash
sudo apt install ruby ruby-dev
sudo gem install bundler
cd bolu-atx.github.io
bundle install
bundle exec jekyll serve
```


#### On MacOS
```bash
xcode-select --install
export SDKROOT=$(xcrun --show-sdk-path)

# Install Homebrew [optional]
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Ruby
brew install ruby

# Install bundler / jekyll in user-mode
gem install --user-install bundler jekyll

# Install dependencies and run development server
cd bolu-atx.github.io
bundle install
bundle exec jekyll serve
```
