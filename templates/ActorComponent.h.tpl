{{COPYRIGHT_HEADER}}

#pragma once

#include "CoreMinimal.h"
{{DIRECT_INCLUDES}}
#include "{{CLASS_NAME}}.generated.h"


UCLASS( ClassGroup=(Custom), meta=(BlueprintSpawnableComponent) )
class {{API_MACRO}} {{CLASS_PREFIX}}{{CLASS_NAME}} : public {{BASE_CLASS_NAME}}
{
	GENERATED_BODY()

public:	
	// Sets default values for this component's properties
	{{CLASS_PREFIX}}{{CLASS_NAME}}();

protected:
	// Called when the game starts
	virtual void BeginPlay() override;

public:	
	// Called every frame
	virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;

		
};
