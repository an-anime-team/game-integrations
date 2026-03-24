# Standard Anime Games Launcher packages index

This repository contains official packages and games integration modules
for [Anime Games Launcher](https://github.com/an-anime-team/anime-games-launcher).

Everything in this repository, if not stated otherwise, is licensed under
[GPL-3.0-or-later](./LICENSE).

## How to be added to this repository?

Since this is the official games repository and is used by default in all the
Anime Games Launcher instances, your game integration and/or package will be
reviewed and must meet certain criteria.

1. It must have a free and open source license and properly reference all the
   code samples taken from other sources.
2. Usage of generative AI must be explicitly noted in the README file of your
   game or package.
3. It must be maintained properly and have long term support (you can't just
   upload a package and expect other people to maintain it).
4. You must provide a communication channel for both developers and community
   members. We must be able to contact you directly, preferably - through our
   Discord server.
5. You must split code that uses extended privileges from the rest of your
   work. I.e., if you need to use process API - you must make a sub-package
   with minimal requried functionality. This sub-package must be designed to
   handle permissions and paths checks to avoid potential security issues.
6. Your game integrations can't pirate game files.
7. Your game integrations can't provide cheats or other unfair game
   modifications for online games.
8. You must be ready to cooperate with other developers and expect that your
   code will be actively reviewed by both the team and other community members.

If you don't meet some of these criteria - you can make your own games
integrations repository, or join some of the community maintained ones. If your
repository will be approved by our team - it can be listed in the official
launcher's repository. Please contact us in Discord for more details.

## Local testing branch

For much better development experience it's recommended to clone the repo 
locally, install `miniserve` (or any other HTTP files sharing tool), checkout to
`local-testing` branch and host the whole repo. This branch contains the same
packages as the main one, except all the links are replaced to 
`http://127.0.0.1:8080`.

Note that this branch is not updated regularly and you might need to merge
the main branch into it.
