#!/usr/bin/python3

'''
This code updates the REPEL table from promed mongodb
'''

from datetime import datetime
import docker
import os
import psycopg2
import pymongo
from pymongo import MongoClient
import time

script_version = 0.1

def valid_post(test_post):
    # FIX: check that it hasn't already been added to repel table
    #      need a flag in mongodb record for this
    is_valid = False
    if ( (len(test_post['epitator_subject_diseaseLabels']) > 0 or
          len(test_post['epitator_keywords_disease']) > 0) and
         len(test_post['epitator_geonames']) > 0 and
         len(test_post['epitator_dates']) > 0 ):
         is_valid = True
    return is_valid

def add_post_repel(cur, valid_post):
    disease_list = valid_post['epitator_subject_diseaseLabels'] + valid_post['epitator_keywords_disease']
    geoname_list = valid_post['epitator_geonames']
    year_list = []
    for curr_json in valid_post['epitator_dates']:
        for curr_date in curr_json['datetime_range']:
            if curr_date.year not in year_list:
                year_list.append(curr_date.year)
    species_list = valid_post['epitator_keywords_species']
    sql_species_array = '{' + ','.join(['"{}"'.format(x) for x in species_list]) + '}'

    n_cases = 0
    for el in valid_post['epitator_counts']:
        if 'case' in el['attributes']:
            n_cases += el['count']

    for curr_disease in disease_list:
        for curr_geoname in geoname_list:
            for curr_year in year_list:
                sql = ''' SELECT * FROM promed
                                   WHERE disease_name='{0}'
                                   AND disease_country='{1}'
                                   AND disease_year={2} '''.format(curr_disease,
                                                                   curr_geoname,
                                                                   curr_year)
                cur.execute(sql)
                if cur.rowcount == 0:
                    sql = ''' INSERT INTO promed(disease_name, disease_country,
                                                 disease_year, disease_species,
                                                 n_posts, n_cases)
                                     VALUES('{0}', '{1}', {2}, '{3}', {4}, {5}) '''.format(curr_disease,
                                                                                           curr_geoname,
                                                                                           curr_year,
                                                                                           sql_species_array,
                                                                                           1, n_cases)
                    cur.execute(sql)
                else:
                    ## FIX: needs to be tested!
                    ## FIX: need to add cases and species
                    row = cur.fetchone()
                    sql_updated_species = ''
                    if len(species_list) > 0:
                        new_species_array = sql_species_array[-1] + ',' + row[4][1:]
                        sql_updated_species = ",disease_species={}".format(new_species_array)
                    sql_updated_cases = ''
                    if n_cases > 0:
                        sql_updated_cases = ',n_cases=n_cases+{}'.format(n_cases)
                    sql = ''' UPDATE promed SET n_posts=n_posts+1 {0} {1}
                                            WHERE disease_name='{2}', disease_country='{3}',
                                                  disease_year={4} '''.format(sql_updated_species,
                                                                              sql_updated_cases,
                                                                              curr_disease,
                                                                              curr_geoname,
                                                                              curr_year)

###########  end utility fucntions, start script content

### make postgres connection

dsn = "host={0} port={1} dbname={2} user={3} password={4}".format(os.environ['POSTGRES_HOST'],
                                                                  os.environ['POSTGRES_PORT'],
                                                                  os.environ['POSTGRES_DB'],
                                                                  os.environ['POSTGRES_USER'],
                                                                  os.environ['POSTGRES_PASSWORD'])
conn = psycopg2.connect(dsn)
cur = conn.cursor()

## create promed postgres table if it doesn't exist

sql = ''' SELECT * FROM information_schema.tables where table_name='promed' '''
cur.execute(sql)
if cur.rowcount == 0:
    sql = ''' CREATE TABLE promed (
                     promed_id SERIAL PRIMARY KEY,
                     disease_name VARCHAR(255) NOT NULL,
                     disease_country VARCHAR(255) NOT NULL,
                     disease_year INTEGER NOT NULL,
                     disease_species VARCHAR(1023),
                     n_posts INTEGER NOT NULL,
                     n_cases INTEGER NOT NULL ) '''
    cur.execute(sql)
    sql = ''' CREATE UNIQUE INDEX idx_promed_disease ON promed(disease_name,
                                                               disease_country,
                                                               disease_year) '''
    cur.execute(sql)


### promed mongodb connection

client = MongoClient('mongo', 27017)
db = client.promed
posts = db.posts
all_posts = posts.find()
for post in all_posts:
    if valid_post(post):
        add_post_repel(cur, post)



cur.close()
conn.commit()
