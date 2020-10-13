#!/usr/bin/python3

'''
This code updates the REPEL table from promed mongodb
'''

from datetime import datetime
import docker
import os
import psycopg2
import pymongo
import time

script_version = 0.3

def add_post_repel(cur, curr_post, mode):
    promed_id = curr_post['promedId']
    promed_url = 'https://promedmail.org/promed-post/?id={}'.format(promed_id)
    subject_description = ''
    if 'subject' in curr_post.keys() and 'description' in curr_post['subject'].keys():
        subject_description = curr_post['subject']['description']
    subject_region = ''
    if 'subject' in curr_post.keys() and 'region' in curr_post['subject'].keys():
        subject_region = curr_post['subject']['region']
    subject_additional_info = ''
    if 'subject' in curr_post.keys() and 'additionalInfo' in curr_post['subject'].keys():
        subject_additional_info = curr_post['subject']['additionalInfo']
    subject_disease_labels = ''
    if 'subject' in curr_post.keys() and 'disease_labels' in curr_post['subject'].keys():
        subject_disease_labels = curr_post['subject']['disease_labels']
    if 'promedDate' in curr_post.keys():
        promed_year = curr_post['promedDate'].year
        if curr_post['promedDate'].month < 7:
            promed_semester = 1
        else:
            promed_semester = 2
    epitator_counts = ''
    if 'epitator_counts' in curr_post.keys():
        epitator_counts = curr_post['epitator_counts']
    epitator_keywords_disease = ''
    if 'epitator_keywords_disease' in curr_post.keys():
        epitator_keywords_disease = curr_post['epitator_keywords_disease']
    epitator_keywords_species = ''
    if 'epitator_keywords_species' in curr_post.keys():
        epitator_keywords_species = curr_post['epitator_keywords_species']
    epitator_geonames_countries = ''
    if 'epitator_geonames' in curr_post.keys():
        epitator_geonames_countries = curr_post['epitator_geonames']

    print('*** record start ***')
    print(promed_id)
    print(promed_url)
    print(subject_description)
    print(subject_region)
    print(subject_additional_info)
    print(subject_disease_labels)
    print(promed_year)
    print(promed_semester)
    print(epitator_counts)
    print(epitator_keywords_disease)
    print(epitator_keywords_species)
    print(epitator_geonames_countries)
    print()

    if mode == 'insert':
        sql = '''INSERT INTO promed_posts(promed_id, promed_url, subject_description,
                                          subject_region, subject_additional_info,
                                          subject_disease_labels, promed_year,
                                          promed_semester, epitator_counts,
                                          epitator_keywords_disease,
                                          epitator_keywords_species,
                                          epitator_geonames, update_script_version)
                        VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)'''
        record_to_insert = (promed_id, promed_url, subject_description, subject_region,
                            subject_additional_info, subject_disease_labels,
                            promed_year, promed_semester, epitator_counts,
                            epitator_keywords_disease, epitator_keywords_species,
                            epitator_geonames_countries, script_version)
        cur.execute(sql, record_to_insert)
    elif mode == 'update':
        sql = '''UPDATE promed_posts SET promed_url=%s, subject_description=%s,
                                         subject_region=%s, subject_additional_info=%s,
                                         subject_disease_labels=%s, promed_year=%s,
                                         promed_semester=%s, epitator_counts=%s,
                                         epitator_keywords_disease=%s,
                                         epitator_keywords_species=%s,
                                         epitator_geonames=%s, update_script_version=%s
                                     WHERE promed_id=%s'''
        record_to_insert = (promed_url, subject_description, subject_region,
                            subject_additional_info, subject_disease_labels,
                            promed_year, promed_semester, epitator_counts,
                            epitator_keywords_disease, epitator_keywords_species,
                            epitator_geonames_countries, script_version, promed_id)
        cur.execute(sql, record_to_insert)


def post_in_db(cur, post):
    sql = "SELECT update_script_version FROM promed_posts WHERE promed_id = %s"
    sql_values = (post['promedId'],)
    cur.execute(sql, sql_values)
    if cur.rowcount == 0:
        return 'insert'
    else:
        row = cur.fetchone()
        if script_version != row[0]:
            return 'update'
        else:
            return 'skip'

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

sql = ''' SELECT * FROM information_schema.tables where table_name='promed_posts' '''
cur.execute(sql)
if cur.rowcount == 0:
    sql = ''' CREATE TABLE promed_posts (
                     promed_id INTEGER PRIMARY KEY,
                     promed_url VARCHAR(255),
                     subject_description VARCHAR(1023),
                     subject_region VARCHAR(255),
                     subject_additional_info VARCHAR(1023),
                     subject_disease_labels VARCHAR(1023),
                     promed_year INTEGER,
                     promed_semester INTEGER,
                     epitator_counts VARCHAR(1023),
                     epitator_keywords_disease VARCHAR(8191),
                     epitator_keywords_species VARCHAR(8191),
                     epitator_geonames VARCHAR(8191),
                     update_script_version REAL ) '''
    cur.execute(sql)


### promed mongodb connection

uri_str = 'mongodb://{0}:{1}@{2}:{3}/{4}'.format(os.getenv('PROMED_USER'),
                                                 os.getenv('PROMED_PASS'),
                                                 os.getenv('PROMED_HOST'),
                                                 os.getenv('PROMED_PORT'),
                                                 os.getenv('PROMED_DB'))
client = pymongo.MongoClient(uri_str)
db = client[os.getenv('PROMED_DB')]

posts = db.posts
all_posts = posts.find()
for post in all_posts:
    how_to_proceed = post_in_db(cur, post)
    if how_to_proceed != 'skip':
        add_post_repel(cur, post, how_to_proceed)

cur.close()
conn.commit()
