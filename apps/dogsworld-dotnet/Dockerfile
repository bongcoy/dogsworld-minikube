# Stage 1: Build aplikasi (.NET Core 3.1 SDK)
# Berjalan di arsitektur mesin pembuat (tanpa emulasi). Hasil publish adalah IL yang netral arsitektur.
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/core/sdk:3.1 AS build
WORKDIR /src

# Restore & Publish aplikasi .NET
COPY ["DogsWorld.csproj", "./"]
RUN dotnet restore "DogsWorld.csproj"
COPY . .
RUN dotnet publish "DogsWorld.csproj" -c Release -o /app/publish

# Stage 2: Runtime Image (.NET Core 3.1 ASP.NET Runtime)
FROM mcr.microsoft.com/dotnet/core/aspnet:3.1 AS final
WORKDIR /app

# Tracer Datadog TIDAK dipasang di image ini.
# Di Kubernetes, tracer disuntikkan otomatis oleh Single Step Instrumentation (SSI).
# Jangan set CORECLR_* di sini karena akan bentrok dengan SSI.

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "DogsWorld.dll"]
