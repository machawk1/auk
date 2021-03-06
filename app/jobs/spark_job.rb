# frozen_string_literal: true

# Methods for Basic Spark Jobs.
class SparkJob < ApplicationJob
  queue_as :spark

  after_perform do
    update_dashboard = Dashboard.find_by(job_id: job_id)
    update_dashboard.end_time = DateTime.now.utc
    update_dashboard.save
  end

  def perform(user_id, collection_id)
    Dashboard.find_or_create_by!(
      job_id: job_id,
      user_id: user_id,
      collection_id: collection_id,
      queue: 'spark',
      start_time: DateTime.now.utc
    )
    spark_shell = ENV['SPARK_SHELL']
    Collection.where('user_id = ? AND collection_id = ?', user_id, collection_id).each do |c|
      collection_path = ENV['DOWNLOAD_PATH'] +
                        '/' + c.account.to_s +
                        '/' + c.collection_id.to_s + '/'
      collection_warcs = collection_path + 'warcs/*.gz'
      collection_derivatives = collection_path + c.user_id.to_s + '/derivatives'
      collection_spark_jobs_path = collection_path + c.user_id.to_s + '/spark_jobs'
      collection_spark_job_file = collection_spark_jobs_path + '/' + c.collection_id.to_s + '.scala'
      FileUtils.rm_rf collection_derivatives
      FileUtils.rm_rf collection_spark_jobs_path
      FileUtils.mkdir_p collection_derivatives
      FileUtils.mkdir_p collection_spark_jobs_path
      FileUtils.mkdir_p collection_derivatives + '/gephi'
      spark_memory_driver = ENV['SPARK_MEMORY_DRIVER']
      spark_network_timeout = ENV['SPARK_NETWORK_TIMEOUT']
      aut_version = ENV['AUT_VERSION']
      spark_threads = ENV['SPARK_THREADS']
      spark_heartbeat_interval = ENV['SPARK_HEARTBEAT_INTERVAL']
      spark_driver_max_result_size = ENV['SPARK_DRIVER_MAXRESULTSIZE']
      spark_job = %(
      import io.archivesunleashed._
      import io.archivesunleashed.app._
      import io.archivesunleashed.matchbox._
      sc.setLogLevel("INFO")
      RecordLoader.loadArchives("#{collection_warcs}", sc).keepValidPages().map(r => ExtractDomain(r.getUrl)).countItems().saveAsTextFile("#{collection_derivatives}/all-domains/output")
      RecordLoader.loadArchives("#{collection_warcs}", sc).keepValidPages().map(r => (r.getCrawlDate, r.getDomain, r.getUrl, RemoveHTML(RemoveHttpHeader(r.getContentString)))).saveAsTextFile("#{collection_derivatives}/all-text/output")
      val links = RecordLoader.loadArchives("#{collection_warcs}", sc).keepValidPages().map(r => (r.getCrawlDate, ExtractLinks(r.getUrl, r.getContentString))).flatMap(r => r._2.map(f => (r._1, ExtractDomain(f._1).replaceAll("^\\\\s*www\\\\.", ""), ExtractDomain(f._2).replaceAll("^\\\\s*www\\\\.", "")))).filter(r => r._2 != "" && r._3 != "").countItems().filter(r => r._2 > 5)
      WriteGraphML(links, "#{collection_derivatives}/gephi/#{c.collection_id}-gephi.graphml")
      sys.exit
      )
      File.open(collection_spark_job_file, 'w') { |file| file.write(spark_job) }
      spark_job_cmd = spark_shell + ' --master local[' + spark_threads + '] --driver-memory ' + spark_memory_driver + ' --conf spark.network.timeout=' + spark_network_timeout + ' --conf spark.executor.heartbeatInterval=' + spark_heartbeat_interval + ' --conf spark.driver.maxResultSize=' + spark_driver_max_result_size + ' --packages "io.archivesunleashed:aut:' + aut_version + '" -i ' + collection_spark_job_file + ' | tee ' + collection_spark_job_file + '.log'
      logger.info 'Executing: ' + spark_job_cmd
      system(spark_job_cmd)
      domain_success = collection_derivatives + '/all-domains/output/_SUCCESS'
      fulltext_success = collection_derivatives + '/all-text/output/_SUCCESS'
      graphml_success = collection_derivatives + '/gephi/' +
                        c.collection_id.to_s + '-gephi.graphml'
      if File.exist?(domain_success) && File.exist?(fulltext_success) &&
         File.exist?(graphml_success) && !File.empty?(graphml_success)
        GraphpassJob.set(queue: :graphpass)
                    .perform_later(user_id, collection_id)
      else
        UserMailer.notify_collection_failed(c.user_id.to_s,
                                            c.collection_id.to_s).deliver_now
        raise 'Collections spark job failed.'
      end
    end
  end
end
