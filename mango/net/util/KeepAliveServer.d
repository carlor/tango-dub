/*******************************************************************************

        copyright:      Copyright (c) 2004 Kris Bell. All rights reserved

        license:        BSD style: $(LICENSE)
        
        version:        Initial release: April 2004    
        
        author:         Kris

*******************************************************************************/

module mango.net.util.KeepAliveServer;

public  import  tango.log.Logger;

public  import  tango.io.model.IConduit;

public  import  mango.net.util.ServerThread,
                mango.net.util.AbstractServer;


private import  tango.core.thread;

private import  tango.io.Buffer,
                tango.io.Exception,
                tango.io.GrowBuffer;

private import  tango.net.ServerSocket;

/******************************************************************************

        Long-running server thread to handle database requests. These
        threads are the equivalent of HTTP "keep-alive" workers, and 
        operate until the client closes the socket or a fatal exception 
        occurs. In the latter case, we close the socket instead which
        will result in a dead socket at the client end.

******************************************************************************/

class KeepAliveThread : Thread
{
        public GrowBuffer      buffer;
        public Logger          logger;
        public char[]          client;

        /**********************************************************************

        **********************************************************************/

        abstract bool service ();

        /**********************************************************************

                Note that the conduit stays open until the client kills it.
                Also note that we use a GrowableBuffer here, which expands
                as necessary to contain larger payloads.

        **********************************************************************/

        this (AbstractServer server, IConduit conduit)
        {
                // create IO buffer with an 8KB initial size
                buffer = new GrowBuffer (conduit, 1024 * 8);

                // get client infomation
                client = server.getRemoteAddress (conduit);

                // save state
                logger = server.getLogger();
        }

        /**********************************************************************
        
                Implement the worker

        **********************************************************************/

        override void run ()
        {
                logger.info (client ~ " starting service handler");
                
                try {
                    while (true)
                          {
                          // wait for input
                          buffer.wait ();

                          // do something with the request 
                          // quit when return is false
                          if (! service)
                                break;
                          }

                    } catch (IOException x)
                             if (! Socket.isHalting)
                                   logger.trace (client ~ " '" ~ x.toString() ~ "'");

                      catch (Object x)
                             logger.fatal (client ~ " '" ~ x.toString() ~ "'");

                // log our halt status
                logger.info (client ~ " halting service handler");

                // make sure we close the conduit ~ the client will see this also
                buffer.getConduit.close ();
        }

        /**********************************************************************
        
        **********************************************************************/

        void exception (char[] msg)
        {
                logger.error (client ~ " " ~ msg);
        }                
}


/******************************************************************************
        
        Extends the AbstractServer to glue DB-server support together.
        Note that there may only be one server running for any given host
        name. This is to make it easier to manage the server(s) via one or
        more http clients. If you require more than one server per machine,
        virtual hosting will need to be provided.

        This server is designed to keep a set of sockets open, rather than
        closing them after each service request. It does this by splitting
        the server-socket listener and the workers ~ there is typically 
        just one listener which, in turn, creates a long-running worker 
        thread to handle the socket during its lifetime. The worker thread
        will die either when the client closes it, or if a fatal exception
        occurs (which the client will see via a socket closure).

        To build a server that services each request directly (and then 
        closes the requesting socket), you would alter the service() method
        to perform the work of DBThread instead, and indicate the number of
        required worker-threads in the DBServer ctor.

******************************************************************************/

class KeepAliveServer : AbstractServer
{
        /**********************************************************************

                Return the protocol in use

        **********************************************************************/

        abstract char[] getProtocol();

        /**********************************************************************

                Return a worker thread

        **********************************************************************/

        abstract KeepAliveThread createWorker (IConduit conduit);

        /**********************************************************************

                Construct this server with the requisite attributes. The 
                'addr' address is the local address we'll be listening on, 
                'threads' represents the number of socket-accept threads, 
                and backlog is the number of "simultaneous" connection 
                requests that a socket layer will buffer on our behalf.

        **********************************************************************/

        this (InternetAddress addr, int threads = 1, int backlog = 100, Logger logger = null)
        {
                super (addr, threads, backlog, logger);
        }

        /**********************************************************************

                Return a text string identifying this server

        **********************************************************************/

        override char[] toString()
        {
                return getProtocol ~ "::host";
        }

        /**********************************************************************

                Create a ServerSocket instance, and mark the socket as 
                reusable such that you don't have to wait before a restart

        **********************************************************************/

        override ServerSocket createSocket (InternetAddress bind, int backlog)
        {
                return new ServerSocket (bind, backlog, true);
        }

        /**********************************************************************

                Create a ServerThread instance. This can be overridden to 
                create other thread-types, perhaps with additional thread-
                level data attached.

        **********************************************************************/

        override ServerThread createThread (ServerSocket socket)
        {
                return new ServerThread (this, socket);
        }

        /**********************************************************************

                Factory method for servicing a request. We just create
                a new ClusterThread to handle requests from the client.
                The thread does not exit until the socket connection is
                broken by the client, or some other exception occurs. 

        **********************************************************************/

        void service (ServerThread socketOpener, IConduit conduit)
        {       
                createWorker(conduit).start();
        }
}


