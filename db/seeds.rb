user = User.create! username: 'pub dic person',
                    email: 'test@pubdictionaries.org',
                    password: 'password',
                    confirmed_at: Time.now

user.dictionaries.create! name: 'EntrezGene',
                          description: 'EntrezGene dictionary',
                          public: true




