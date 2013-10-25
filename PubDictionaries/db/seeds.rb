# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)


Entry.delete_all

# description field has three values, semantic class, gene ID, and texonomy ID, separated with | character
entrezgene_entries = Entry.create( [
	{ title: 'BRCA1', 
	  label: 'Gene',
	  uri: '672|9606',
	  },  
	{ title: 'fukutin', 
	  label: 'Gene',
	  uri: '2218|9606',
	  }, 
	{ title: 'cystic fibrosis transmembrane conductance regulator', 
	  label: 'Gene',
	  uri: '12638|10090',
	  }, 
	{ title: 'NFKB1', 
	  label: 'Gene',
	  uri: '4790|9606', 
	  }, 
	{ title: 'nuclear factor of kappa light polypeptide gene enhancer in B-cells 1', 
	  label: 'Gene',
	  uri: '4790|9606',
	  },
	{ title: 'p53', 
	  label: 'Gene',
	  uri: '4790|9606',
	  },
	{ title: 'nuclear factor of kappa light polypeptide gene enhancer in B cells 1, p105', 
	  label: 'Gene',
	  uri: '18033|10090',
	  },
    { title: 'Nfkb1', 
	  label: 'Gene',
	  uri: '18033|10090',
	  },
    { title: 'RELA', 
	  label: 'Gene',
	  uri: '5970|9606',
	  },
    { title: 'Nfkb1', 
	  label: 'Gene',
	  uri: '81736|10116',
	  },
    { title: 'EBP-1', 
	  label: 'Gene',
	  uri: '81736|10116',
	  },
] )


Dictionary.delete_all

Dictionary.create(
	title: 'EntrezGene',
	creator: 'priancho@gmail.com',
	description:'EntrezGene dictionary',
	entries: entrezgene_entries,
	)



