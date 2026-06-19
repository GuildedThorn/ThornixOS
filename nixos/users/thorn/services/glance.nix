{ ... }:
{
  services.glance = {
    enable = true;

    settings = {
      server = {
        host = "0.0.0.0";
        port = 8080;
      };

      pages = [

        {
          name = "Home";
          columns = [

            {
              size = "small";
              widgets = [

                {
                  type = "clock";
                  hour-format = "12h";
                }

                {
                  type = "weather";
                  location = "Alsip";
                  units = "imperial";
                }

                {
                  type = "markets";
                  markets = [
                    {
                      symbol = "SPY";
                      name = "S&P 500";
                      chart-link = "https://www.tradingview.com/chart/?symbol=AMEX%3AVOO";
                    }
                    {
                      symbol = "PTLO";
                      name = "Portillos";
                      chart-link = "https://www.tradingview.com/chart/?symbol=PTLO";
                    }
                    {
                      symbol = "NVDA";
                      name = "NVIDIA";
                      chart-link = "https://www.tradingview.com/chart/?symbol=NVDA";
                    }
                  ];
                }

              ];
            }

            {
              size = "full";
              widgets = [
                {
                  type = "search";
                  search-engine = "duckduckgo";
                  new-tab = true;
                  autofocus = true;
                  bangs = [
                    {
                      title = "Youtube";
                      shortcut = "!yt";
                      url = "https://www.youtube.com/results?search_query={QUERY}";
                    }
                    {
                      title = "Steam";
                      shortcut = "!steam";
                      url = "https://store.steampowered.com/search/?term={QUERY}";
                    }
                    {
                      title = "Amazon";
                      shortcut = "!amazon";
                      url = "https://www.amazon.com/s?k={QUERY}";
                    }
                    {
                      title = "Reddit";
                      shortcut = "!rd";
                      url = "https://www.reddit.com/search?q={QUERY}";
                    }
                    {
                      title = "FlightAware";
                      shortcut = "!fa";
                      url = "https://www.flightaware.com/live/flight/{QUERY}";
                    }
                  ];
                }
              ];
            }

            {
              size = "small";
              widgets = [

                {
                  type = "reddit";
                  subreddit = "selfhosted";
                  show-thumbnails = true;
                }

              ];
            }

          ];
        }

        {
          name = "Feeds";
          columns = [
            {
              size = "full";
              widgets = [

                {
                  type = "rss";
                  title = "Tech News";
                  limit = 10;

                  feeds = [
                    {
                      url = "https://hnrss.org/frontpage";
                      title = "Hacker News";
                    }
                    {
                      url = "https://www.theverge.com/rss/index.xml";
                      title = "The Verge";
                    }
                  ];
                }

              ];
            }

          ];
        }

        {
          name = "Videos";
          columns = [

            {
              size = "full";
              widgets = [

                {
                  type = "videos";
                  channels = [
                    "UCa6eh7gCkpPo5XXUDfygQQA"
                    "UClcE-kVhqyiHCcjYwcpfj9w"
                  ];
                }

                {
                  type = "twitch-channels";
                  channels = [
                    "s1ren_official"
                  ];
                }

              ];
            }
          ];
        }

        {
          name = "Gaming";
          columns = [
            {
              size = "small";
              widgets = [
                {
                  type = "twitch-top-games";
                  limit = 20;
                  collapse-after = 13;
                  exclude = [
                    "just-chatting"
                    "pools-hot-tubs-and-beaches"
                    "music"
                    "art"
                    "asmr"
                  ];
                }
              ];
            }
            {
              size = "full";
              widgets = [
                {
                  type = "group";
                  widgets = [
                    {
                      type = "reddit";
                      show-thumbnails = true;
                      subreddit = "pcgaming";
                    }
                    {
                      type = "reddit";
                      subreddit = "games";
                    }
                  ];
                }
                {
                  type = "videos";
                  style = "grid-cards";
                  collapse-after-rows = 3;
                  channels = [
                    "UCNvzD7Z-g64bPXxGzaQaa4g" # gameranx
                    "UCZ7AeeVbyslLM_8-nVy2B8Q" # Skill Up
                    "UCHDxYLv8iovIbhrfl16CNyg" # GameLinked
                    "UC9PBzalIcEQCsiIkq36PyUA" # Digi
                  ];
                }
              ];
            }
            {
              size = "small";
              widgets = [
                {
                  type = "reddit";
                  subreddit = "gamingnews";
                  limit = 7;
                  style = "vertical-cards";
                }
              ];
            }
          ];
        }

        {
          name = "Services";
          columns = [

            {
              size = "full";
              widgets = [
                {
                  type = "monitor";
                  cache = "1m";
                  title = "Services";

                  sites = [
                    {
                      title = "Jellyfin";
                      url = "https://truenas.guildedthorn.arpa:8920";
                    }
                    {
                      title = "Pfsense";
                      url = "https://pfsense.guildedthorn.arpa";
                    }
                    {
                      title = "TrueNAS";
                      url = "https://truenas.guildedthorn.arpa";
                    }
                    {
                      title = "SearXNG";
                      url = "https://mitm.guildedthorn.arpa/searxng/stats";
                    }
                  ];

                }

                {
                  type = "repository";
                  repository = "GuildedThorn/ThornixOS";
                  pull-requests-limit = 5;
                  issues-limit = 3;
                  commits-limit = 3;
                }

              ];
            }
          ];
        }
      ];
    };
  };
}
