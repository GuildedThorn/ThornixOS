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
                    }
                    {
                      symbol = "PTLO";
                      name = "Portillos";
                      chart-link = "https://www.tradingview.com/chart/?symbol=PTLO";
                    }
                    {
                      symbol = "NVDA";
                      name = "NVIDIA";
                    }
                  ];
                }

              ];
            }

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
                    {
                      title = "Pihole";
                      url = "https://mitm.guildedthorn.arpa/admin/login";
                    }
                  ];

                }

              ];
            }
          ];
        }
      ];
    };
  };
}
